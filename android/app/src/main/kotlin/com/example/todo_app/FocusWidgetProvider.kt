package com.example.todo_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Renders the resizable Focus home-screen widget.
 *
 * Architecture change (ListView migration)
 * ────────────────────────────────────────
 * The previous implementation used a fixed LinearLayout with five hardcoded
 * rows and [android.widget.RemoteViews.setOnClickPendingIntent] per row.
 * That approach had three problems:
 *
 *  1. Hard cap of five rows — extra payload rows were silently dropped.
 *  2. Not scrollable — LinearLayout never scrolls.
 *  3. Complete action broken — all rows shared PendingIntent request-code 0,
 *     so FLAG_UPDATE_CURRENT meant only the last row's URI was kept.
 *
 * The current implementation:
 *  - Uses a [android.widget.ListView] backed by [FocusWidgetListService]
 *    (a RemoteViewsService). The factory reads every row from the payload
 *    with no hard cap; the list scrolls naturally.
 *  - Uses [android.widget.RemoteViews.setPendingIntentTemplate] +
 *    [android.widget.RemoteViews.setOnClickFillInIntent] for the complete
 *    action. The template targets [WidgetCompleteReceiver] with FLAG_MUTABLE
 *    so the per-row fill-in extras are merged correctly at click time.
 *  - The header row keeps its own tap-to-open-app intent.
 *
 * Interaction:
 *  - Tapping the header (or anywhere outside the list) opens the app.
 *  - Tapping the active check circle on the current step fires a broadcast
 *    to [WidgetCompleteReceiver], which forwards to the home_widget
 *    background isolate so Flutter can process the completion.
 */
class FocusWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload   = widgetData.getString("focus_payload", null)
        val rowCount  = parseRowCount(payload)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_widget)

            // ── Header tap → open app ──────────────────────────────────────
            views.setOnClickPendingIntent(
                R.id.focus_widget_header,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            // ── Empty / non-empty state ────────────────────────────────────
            if (rowCount == 0) {
                views.setViewVisibility(R.id.focus_widget_empty, View.VISIBLE)
                views.setViewVisibility(R.id.focus_list, View.GONE)
                views.setTextViewText(R.id.focus_widget_count, "")
            } else {
                views.setViewVisibility(R.id.focus_widget_empty, View.GONE)
                views.setViewVisibility(R.id.focus_list, View.VISIBLE)
                views.setTextViewText(R.id.focus_widget_count, rowCount.toString())
            }

            // ── ListView adapter (FocusWidgetListService) ──────────────────
            val serviceIntent = Intent(context, FocusWidgetListService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            views.setRemoteAdapter(R.id.focus_list, serviceIntent)

            // ── Complete-step PendingIntent template ───────────────────────
            // Must be FLAG_MUTABLE so the per-row fill-in extras (goalId,
            // subtaskId, isCurrent) set by the factory can be merged in.
            val templateIntent = Intent(context, WidgetCompleteReceiver::class.java).apply {
                action = WidgetCompleteReceiver.ACTION_COMPLETE
            }
            val mutFlag = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val templatePendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                templateIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or mutFlag,
            )
            views.setPendingIntentTemplate(R.id.focus_list, templatePendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)

            // updateAppWidget refreshes the static views (header, count, empty
            // state) but does NOT cause the ListView's RemoteViewsFactory to
            // reload. Without this call the factory keeps serving its cached
            // rows, so adding / removing goals or toggling "show all goals"
            // wouldn't appear on the widget until the system happened to rebind
            // the service (e.g. after a reboot). notifyAppWidgetViewDataChanged
            // explicitly triggers RemoteViewsFactory.onDataSetChanged, which
            // re-reads the latest payload from SharedPreferences.
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.focus_list)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun parseRowCount(payload: String?): Int {
        if (payload.isNullOrEmpty()) return 0
        return try {
            JSONObject(payload).getJSONArray("rows").length()
        } catch (_: Exception) {
            0
        }
    }
}
