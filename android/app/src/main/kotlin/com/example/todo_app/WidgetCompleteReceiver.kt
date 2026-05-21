package com.example.todo_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetBackgroundService
import io.flutter.FlutterInjector

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
 * goalId/subtaskId from extras, reconstructs the todofocus:// URI, and forwards
 * to [HomeWidgetBackgroundService] exactly as
 * [es.antonborri.home_widget.HomeWidgetBackgroundReceiver] would.
 */
class WidgetCompleteReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_GOAL_ID    = "goalId"
        const val EXTRA_SUBTASK_ID = "subtaskId"
        const val EXTRA_IS_CURRENT = "isCurrent"

        /** Action string set on the template intent so this receiver can filter it. */
        const val ACTION_COMPLETE = "com.example.todo_app.WIDGET_COMPLETE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Bail on non-current rows (locked steps were given no fill-in, but
        // be defensive in case some path reaches here with isCurrent=false).
        if (!intent.getBooleanExtra(EXTRA_IS_CURRENT, false)) return

        val goalId    = intent.getStringExtra(EXTRA_GOAL_ID)    ?: return
        val subtaskId = intent.getStringExtra(EXTRA_SUBTASK_ID) ?: return

        // Reconstruct the URI that FocusWidgetService (Dart) and the Flutter
        // background callback expect.
        val uri = Uri.parse("todofocus://complete?goalId=$goalId&subtaskId=$subtaskId")

        // Mirror what HomeWidgetBackgroundReceiver does: initialise Flutter then
        // enqueue the work so the Dart background isolate can process it.
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(context)
        flutterLoader.ensureInitializationComplete(context, null)

        val bgIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = uri
        }
        HomeWidgetBackgroundService.enqueueWork(context, bgIntent)
    }
}
