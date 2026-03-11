package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class PracticeWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        return PracticeViewsFactory(applicationContext, widgetId)
    }
}

class PracticeViewsFactory(
    private val context: Context,
    private val widgetId: Int
) : RemoteViewsService.RemoteViewsFactory {

    private data class PracticeItem(
        val id: Int,
        val name: String,
        val type: String,           // habit, tracker, scheduled, task
        val targetSets: Int,
        val completedSets: Int,
        val isDue: Boolean,
        val nextDue: String,
        val daysOverdue: Int,
        val scheduleLabel: String,
        val slotNames: List<String>,  // all slots from config (e.g. ["morning","bedtime"])
        val slotsDue: List<String>    // remaining uncompleted slots
    ) {
        val isDailySlots get() = slotNames.isNotEmpty()
        val isComplete get() = if (isDailySlots) slotsDue.isEmpty() else completedSets >= targetSets
    }

    private var items = listOf<PracticeItem>()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        // Read per-instance filter (fallback to legacy global, then "All")
        val filter = prefs.getString("practice_filter_$widgetId", null)
            ?: prefs.getString("practice_filter", "All")
            ?: "All"

        // Load ALL practices then filter locally
        val totalCount = prefs.getInt("all_practice_count", 0)
        val all = (0 until totalCount).mapNotNull { i ->
            val cat = prefs.getString("all_practice_${i}_category", "") ?: ""
            if (filter != "All" && cat != filter) return@mapNotNull null
            PracticeItem(
                id = prefs.getInt("all_practice_${i}_id", 0),
                name = prefs.getString("all_practice_${i}_name", "") ?: "",
                type = prefs.getString("all_practice_${i}_type", "habit") ?: "habit",
                targetSets = prefs.getInt("all_practice_${i}_target_sets", 1),
                completedSets = prefs.getInt("all_practice_${i}_completed_sets", 0),
                isDue = prefs.getBoolean("all_practice_${i}_is_due", true),
                nextDue = prefs.getString("all_practice_${i}_next_due", "") ?: "",
                daysOverdue = prefs.getInt("all_practice_${i}_days_overdue", 0),
                scheduleLabel = prefs.getString("all_practice_${i}_schedule_label", "") ?: "",
                slotNames = (prefs.getString("all_practice_${i}_slot_names", "") ?: "")
                    .split(",").filter { it.isNotEmpty() },
                slotsDue = (prefs.getString("all_practice_${i}_slots_due", "") ?: "")
                    .split(",").filter { it.isNotEmpty() }
            )
        }

        // Sort: due items first, then not-due at the bottom
        items = all.sortedWith(compareBy(
            { !it.isDue },                                              // due first
            { it.isComplete },                                          // incomplete before complete
            { -it.daysOverdue }                                         // most overdue first
        ))
    }

    override fun getCount() = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= items.size) {
            return RemoteViews(context.packageName, R.layout.practice_widget_item)
        }
        val item = items[position]
        val views = RemoteViews(context.packageName, R.layout.practice_widget_item)

        // Determine graying: not-due scheduled items get dimmed
        val isGrayed = !item.isDue && !item.isComplete

        // Name text
        views.setTextViewText(R.id.practice_item_name, item.name)
        views.setTextColor(
            R.id.practice_item_name,
            when {
                isGrayed -> 0xFF666666.toInt()    // dim for not-due
                item.isComplete -> 0xFF777777.toInt()      // muted for complete
                else -> 0xFFE0E0E0.toInt()         // normal
            }
        )

        // Set button IDs
        val setIds = arrayOf(
            R.id.practice_item_set_0,
            R.id.practice_item_set_1,
            R.id.practice_item_set_2
        )

        if (item.isDailySlots) {
            // --- Daily slots rendering ---
            // Subtitle: slot names with strikethrough on completed ones
            val slotLabels = item.slotNames.mapIndexed { _, slot ->
                val done = slot !in item.slotsDue
                Pair(slot, done)
            }
            val subtitleBuilder = android.text.SpannableStringBuilder()
            for ((idx, pair) in slotLabels.withIndex()) {
                val (slot, done) = pair
                val start = subtitleBuilder.length
                subtitleBuilder.append(slot)
                if (done) {
                    subtitleBuilder.setSpan(
                        StrikethroughSpan(), start, subtitleBuilder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    subtitleBuilder.setSpan(
                        ForegroundColorSpan(0xFF666666.toInt()), start, subtitleBuilder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                if (idx < slotLabels.size - 1) subtitleBuilder.append("  ·  ")
            }
            views.setViewVisibility(R.id.practice_item_subtitle, View.VISIBLE)
            views.setTextViewText(R.id.practice_item_subtitle, subtitleBuilder)
            views.setTextColor(R.id.practice_item_subtitle, 0xFF9E9E9E.toInt())

            // Circles: one per slot, max 3
            for (s in setIds.indices) {
                if (s < item.slotNames.size) {
                    val slotName = item.slotNames[s]
                    val isDone = slotName !in item.slotsDue
                    views.setViewVisibility(setIds[s], View.VISIBLE)
                    views.setImageViewResource(
                        setIds[s],
                        if (isDone) R.drawable.ic_check_circle else R.drawable.ic_check_circle_outline
                    )

                    if (item.id > 0) {
                        val uri = if (isDone) {
                            "brainapp://practice-undo/${item.id}?slot=$slotName"
                        } else {
                            "brainapp://practice-log/${item.id}?slot=$slotName"
                        }
                        views.setOnClickFillInIntent(
                            setIds[s],
                            Intent().apply { data = Uri.parse(uri) }
                        )
                    }
                } else {
                    views.setViewVisibility(setIds[s], View.GONE)
                }
            }
        } else {
            // --- Regular practice rendering ---
            // Subtitle: schedule info for scheduled types, "overdue" for overdue items
            val subtitle = when {
                item.daysOverdue > 0 && item.isDue -> "${item.daysOverdue}d overdue"
                isGrayed && item.nextDue.isNotEmpty() -> nextDueLabel(item.nextDue)
                item.scheduleLabel.isNotEmpty() -> item.scheduleLabel
                else -> ""
            }
            if (subtitle.isNotEmpty()) {
                views.setViewVisibility(R.id.practice_item_subtitle, View.VISIBLE)
                views.setTextViewText(R.id.practice_item_subtitle, subtitle)
                views.setTextColor(
                    R.id.practice_item_subtitle,
                    if (item.daysOverdue > 0 && item.isDue) 0xFFFF6B6B.toInt()
                    else 0xFF9E9E9E.toInt()
                )
            } else {
                views.setViewVisibility(R.id.practice_item_subtitle, View.GONE)
            }

            // Set buttons — show based on targetSets
            for (s in setIds.indices) {
                if (s < item.targetSets) {
                    val isDone = (s + 1) <= item.completedSets
                    views.setViewVisibility(setIds[s], View.VISIBLE)
                    views.setImageViewResource(
                        setIds[s],
                        if (isDone) R.drawable.ic_check_circle else R.drawable.ic_check_circle_outline
                    )

                    if (item.id > 0) {
                        val uri = if (isDone) {
                            "brainapp://practice-undo/${item.id}"
                        } else {
                            "brainapp://practice-log/${item.id}"
                        }
                        views.setOnClickFillInIntent(
                            setIds[s],
                            Intent().apply { data = Uri.parse(uri) }
                        )
                    }
                } else {
                    views.setViewVisibility(setIds[s], View.GONE)
                }
            }
        }

        return views
    }

    private fun nextDueLabel(nextDue: String): String {
        if (nextDue.isEmpty()) return ""
        try {
            val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            val dueDate = sdf.parse(nextDue) ?: return nextDue
            val today = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.time
            val diff = ((dueDate.time - today.time) / (1000 * 60 * 60 * 24)).toInt()
            return when {
                diff <= 0 -> "today"
                diff == 1 -> "tomorrow"
                diff < 7 -> "in ${diff}d"
                else -> sdf.format(dueDate)
            }
        } catch (_: Exception) {
            return nextDue
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = items.getOrNull(position)?.id?.toLong() ?: position.toLong()
    override fun hasStableIds() = true
    override fun onDestroy() {}
}
