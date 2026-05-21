package com.example.todo_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Renders the resizable Focus home-screen widget.
 *
 * Data arrives as a JSON string under "focus_payload", pushed from Dart by
 * FocusWidgetService whenever the focus queue changes. RemoteViews can't
 * loop, so five fixed rows are shown or hidden to match the payload.
 *
 * Interaction:
 *  - tapping anywhere on the widget opens the app;
 *  - tapping the current step's circle fires a home_widget background
 *    broadcast that completes the step without opening the app.
 */
class FocusWidgetProvider : HomeWidgetProvider() {

    private data class RowIds(
        val container: Int,
        val check: Int,
        val step: Int,
        val title: Int,
    )

    private val rowIds = listOf(
        RowIds(R.id.row_0, R.id.row_0_check, R.id.row_0_step, R.id.row_0_title),
        RowIds(R.id.row_1, R.id.row_1_check, R.id.row_1_step, R.id.row_1_title),
        RowIds(R.id.row_2, R.id.row_2_check, R.id.row_2_step, R.id.row_2_title),
        RowIds(R.id.row_3, R.id.row_3_check, R.id.row_3_step, R.id.row_3_title),
        RowIds(R.id.row_4, R.id.row_4_check, R.id.row_4_step, R.id.row_4_title),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload = widgetData.getString("focus_payload", null)
        val rows = parseRows(payload)
        val compact = parseLayout(payload) == "compact"

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_widget)

            // Whole-widget tap opens the app.
            views.setOnClickPendingIntent(
                R.id.focus_widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            if (rows.isEmpty()) {
                views.setViewVisibility(R.id.focus_widget_empty, View.VISIBLE)
                views.setTextViewText(R.id.focus_widget_count, "")
            } else {
                views.setViewVisibility(R.id.focus_widget_empty, View.GONE)
                views.setTextViewText(R.id.focus_widget_count, rows.size.toString())
            }

            for ((i, ids) in rowIds.withIndex()) {
                if (i >= rows.size) {
                    views.setViewVisibility(ids.container, View.GONE)
                    continue
                }
                val row = rows[i]
                views.setViewVisibility(ids.container, View.VISIBLE)
                views.setTextViewText(ids.step, row.optString("step"))

                // Compact layout drops the goal-title line for a denser row.
                if (compact) {
                    views.setViewVisibility(ids.title, View.GONE)
                } else {
                    views.setViewVisibility(ids.title, View.VISIBLE)
                    val emoji = row.optString("goalEmoji")
                    val title = row.optString("goalTitle")
                    views.setTextViewText(
                        ids.title,
                        if (emoji.isNotEmpty()) "$emoji  $title" else title,
                    )
                }

                if (row.optBoolean("isCurrent")) {
                    // The actionable step — circle completes it in the background.
                    views.setImageViewResource(
                        ids.check, R.drawable.ic_widget_check_active,
                    )
                    val uri = Uri.parse(
                        "todofocus://complete" +
                            "?goalId=" + row.optString("goalId") +
                            "&subtaskId=" + row.optString("subtaskId"),
                    )
                    views.setOnClickPendingIntent(
                        ids.check,
                        HomeWidgetBackgroundIntent.getBroadcast(context, uri),
                    )
                } else {
                    // Queued — locked dot, taps fall through to "open app".
                    views.setImageViewResource(
                        ids.check, R.drawable.ic_widget_check_locked,
                    )
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun parseRows(payload: String?): List<JSONObject> {
        if (payload.isNullOrEmpty()) return emptyList()
        return try {
            val arr = JSONObject(payload).getJSONArray("rows")
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun parseLayout(payload: String?): String {
        if (payload.isNullOrEmpty()) return ""
        return try {
            JSONObject(payload).optString("layout")
        } catch (e: Exception) {
            ""
        }
    }
}
