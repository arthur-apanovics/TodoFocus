package com.example.todo_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver

/**
 * Broadcast receiver that handles the "mark step complete" action from the
 * Focus home-screen widget's ListView rows.
 *
 * Background
 * ──────────
 * RemoteViewsFactory rows must use [android.widget.RemoteViews.setOnClickFillInIntent]
 * (not [android.widget.RemoteViews.setOnClickPendingIntent]). The fill-in intent is
 * merged at click-time with a template PendingIntent set on the ListView via
 * [android.widget.RemoteViews.setPendingIntentTemplate]. That template must be
 * FLAG_MUTABLE so the merge can substitute the per-row extras.
 *
 * [es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast] creates an
 * IMMUTABLE PendingIntent, making it unsuitable as a template. This receiver
 * bridges the gap: it is the target of a MUTABLE template, extracts the
 * goalId/subtaskId from extras, reconstructs the `todofocus://` URI, and
 * delegates straight to [HomeWidgetBackgroundReceiver]. Letting the plugin's
 * own receiver do the Flutter init + JobIntentService enqueue is far more
 * reliable than re-implementing those calls here — earlier versions of this
 * receiver that re-implemented the bridge crashed with "Unable to start
 * receiver" due to subtle Flutter/JobScheduler init races.
 *
 * `BroadcastReceiver` has no lifecycle state outside of `onReceive`, so
 * instantiating it directly is safe.
 */
class WidgetCompleteReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_GOAL_ID    = "goalId"
        const val EXTRA_SUBTASK_ID = "subtaskId"
        const val EXTRA_IS_CURRENT = "isCurrent"

        /** Action string set on the template intent so this receiver can filter it. */
        const val ACTION_COMPLETE = "com.example.todo_app.WIDGET_COMPLETE"

        private const val TAG = "WidgetCompleteReceiver"
        private const val HOME_WIDGET_BG_ACTION = "es.antonborri.home_widget.action.BACKGROUND"
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            // Locked rows were given no fill-in, but be defensive in case some
            // path reaches here with isCurrent=false.
            if (!intent.getBooleanExtra(EXTRA_IS_CURRENT, false)) return

            val goalId    = intent.getStringExtra(EXTRA_GOAL_ID)    ?: return
            val subtaskId = intent.getStringExtra(EXTRA_SUBTASK_ID) ?: return

            // Reconstruct the URI that FocusWidgetService (Dart) and the
            // background callback expect, then hand it to home_widget's own
            // receiver. That receiver runs the Flutter loader and enqueues the
            // work onto HomeWidgetBackgroundService — all without us having to
            // touch FlutterInjector or JobIntentService directly.
            val uri = Uri.parse("todofocus://complete?goalId=$goalId&subtaskId=$subtaskId")
            val bgIntent = Intent(HOME_WIDGET_BG_ACTION).apply { data = uri }
            HomeWidgetBackgroundReceiver().onReceive(context, bgIntent)
        } catch (e: Throwable) {
            // Never crash the receiver — Android wraps any throw in
            // "Unable to start receiver" and surfaces it as a fatal ANR-style
            // dialog. Log and move on.
            Log.e(TAG, "Failed to forward widget completion", e)
        }
    }
}
