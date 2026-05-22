package com.example.todo_app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject
import java.io.File

/**
 * RemoteViewsService that supplies an adapter for the Focus widget's ListView.
 *
 * Android's home-screen widget framework requires a Service to back any
 * AdapterView (ListView / GridView). This service creates a
 * [FocusWidgetRowFactory] which reads the JSON payload written by the Flutter
 * side and produces one RemoteViews per row — without any hard limit on row
 * count. The ListView itself provides the scrolling.
 */
class FocusWidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        FocusWidgetRowFactory(applicationContext)
}

/**
 * Builds one [RemoteViews] per row from the "focus_payload" JSON stored by
 * [FocusWidgetService] (Dart) via the home_widget shared-preferences bridge.
 *
 * Row shape (from the Dart payload):
 * ```
 * { goalId, subtaskId, goalTitle, goalEmoji, step,
 *   isCurrent, isFirstInGroup }
 * ```
 *
 * Visual behaviour:
 * - [isFirstInGroup] + position > 0 → show the divider line above the row.
 * - [isCurrent] → show the active check circle; attach the fill-in intent so
 *   the [setPendingIntentTemplate] on the ListView can fire [WidgetCompleteReceiver].
 * - layout == "compact" → hide the goal-title line.
 */
private class FocusWidgetRowFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    private var rows: List<JSONObject> = emptyList()
    private var layoutName: String = ""

    // Per-render bitmap cache so the same icon isn't decoded once per row.
    // Cleared on every onDataSetChanged so updated PNGs are picked up.
    private val iconBitmapCache = HashMap<String, Bitmap?>()

    // Keep the icon-key prefix in lock-step with FocusWidgetService.iconKeyPrefix.
    companion object {
        private const val ICON_KEY_PREFIX = "goal_icon_"
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override fun onCreate() { load() }
    override fun onDataSetChanged() {
        iconBitmapCache.clear()
        load()
    }
    override fun onDestroy() {}

    // ── Data loading ──────────────────────────────────────────────────────

    private fun load() {
        val prefs = HomeWidgetPlugin.getData(context)
        val payload = prefs.getString("focus_payload", null)
        if (payload.isNullOrEmpty()) {
            rows = emptyList()
            layoutName = ""
            return
        }
        try {
            val json = JSONObject(payload)
            layoutName = json.optString("layout", "")
            val arr = json.getJSONArray("rows")
            rows = (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (_: Exception) {
            rows = emptyList()
        }
    }

    /// Resolves an `emoji` name (e.g. "rocket") to a decoded bitmap rendered
    /// by Dart side via HomeWidget.renderFlutterWidget. Returns null when:
    ///   • the name is blank,
    ///   • no PNG has been rasterised for it yet (cold start, or legacy
    ///     unicode-emoji string with no catalog entry — Dart skips those),
    ///   • the file moved or got purged since it was written.
    /// Caller falls back to the text-prefix path on null.
    private fun loadIconBitmap(name: String): Bitmap? {
        if (name.isEmpty()) return null
        iconBitmapCache[name]?.let { return it }
        if (iconBitmapCache.containsKey(name)) return null
        val prefs = HomeWidgetPlugin.getData(context)
        val path = prefs.getString("$ICON_KEY_PREFIX$name", null)
        val bitmap = if (!path.isNullOrEmpty() && File(path).exists()) {
            try { BitmapFactory.decodeFile(path) } catch (_: Exception) { null }
        } else {
            null
        }
        iconBitmapCache[name] = bitmap
        return bitmap
    }

    // ── RemoteViewsFactory ────────────────────────────────────────────────

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = rows.getOrNull(position)
            ?: return RemoteViews(context.packageName, R.layout.focus_widget_row)

        val rv = RemoteViews(context.packageName, R.layout.focus_widget_row)

        val step = row.optString("step")
        val goalTitle = row.optString("goalTitle")
        val goalEmoji = row.optString("goalEmoji")
        val isCurrent = row.optBoolean("isCurrent")
        val isFirstInGroup = row.optBoolean("isFirstInGroup")
        val compact = layoutName == "compact"

        // ── Step text ──────────────────────────────────────────────────────
        rv.setTextViewText(R.id.row_step, step)

        // ── Per-row goal title ─────────────────────────────────────────────
        // Always hidden in the new design — the labelled divider above each
        // group carries the goal title, so a per-row repetition would be
        // redundant. The row_goal_title view is kept in the layout only as a
        // legacy slot in case it's ever wanted back.
        rv.setViewVisibility(R.id.row_goal_title, View.GONE)

        // ── Group divider (labelled with the goal title) ───────────────────
        // Shown above the first row of every goal group, including row 0 —
        // it acts as the group header. Compact layout hides it for maximum
        // density, mirroring how compact already suppresses goal context.
        if (isFirstInGroup && !compact) {
            rv.setViewVisibility(R.id.row_divider, View.VISIBLE)
            // Try to render the icon as a bitmap (the proper, themed path).
            // If we have no bitmap (no rendered PNG yet, or legacy unicode
            // emoji string), prefix the title with the raw `goalEmoji`
            // string so Unicode-emoji goals still display something.
            val iconBitmap = loadIconBitmap(goalEmoji)
            if (iconBitmap != null) {
                rv.setViewVisibility(R.id.row_divider_icon, View.VISIBLE)
                rv.setImageViewBitmap(R.id.row_divider_icon, iconBitmap)
                rv.setTextViewText(R.id.row_divider_title, goalTitle)
            } else {
                rv.setViewVisibility(R.id.row_divider_icon, View.GONE)
                rv.setTextViewText(
                    R.id.row_divider_title,
                    if (goalEmoji.isNotEmpty()) "$goalEmoji  $goalTitle"
                    else goalTitle,
                )
            }
        } else {
            rv.setViewVisibility(R.id.row_divider, View.GONE)
        }

        // ── Check button ───────────────────────────────────────────────────
        if (isCurrent) {
            rv.setImageViewResource(R.id.row_check, R.drawable.ic_widget_check_active)
            // Fill-in intent merged with the ListView's pending-intent template
            // (set in FocusWidgetProvider via setPendingIntentTemplate).
            // WidgetCompleteReceiver extracts these extras and forwards the
            // completion request to the home_widget background mechanism.
            val fillIn = Intent().apply {
                putExtra(WidgetCompleteReceiver.EXTRA_GOAL_ID, row.optString("goalId"))
                putExtra(WidgetCompleteReceiver.EXTRA_SUBTASK_ID, row.optString("subtaskId"))
                putExtra(WidgetCompleteReceiver.EXTRA_IS_CURRENT, true)
            }
            rv.setOnClickFillInIntent(R.id.row_check, fillIn)
        } else {
            rv.setImageViewResource(R.id.row_check, R.drawable.ic_widget_check_locked)
            // Locked rows are not interactive — no fill-in intent.
        }

        return rv
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}
