package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import android.app.PendingIntent
import android.content.Intent

class PracticeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = buildPracticeView(context, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun buildPracticeView(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.practice_widget)
        val count = widgetData.getInt("practice_count", 0)
        val filter = widgetData.getString("practice_filter", "All") ?: "All"

        // Header: category name (tappable → opens filter activity)
        views.setTextViewText(R.id.practice_category, if (filter == "All") "All Practices" else filter)

        val filterIntent = Intent(context, WidgetFilterActivity::class.java).apply {
            data = Uri.parse("brainapp://widget-filter?type=practices")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val filterPending = PendingIntent.getActivity(
            context, 300, filterIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.practice_category, filterPending)

        // Count completed
        var completedCount = 0
        for (i in 0 until count) {
            val targetSets = widgetData.getInt("practice_${i}_target_sets", 1)
            val completedSets = widgetData.getInt("practice_${i}_completed_sets", 0)
            if (completedSets >= targetSets) completedCount++
        }

        // Progress text
        views.setTextViewText(R.id.practice_progress, "$completedCount/$count")

        // Empty state
        views.setViewVisibility(R.id.practice_empty, if (count > 0) View.GONE else View.VISIBLE)

        data class PracticeRow(
            val rowId: Int,
            val nameId: Int,
            val setIds: Array<Int>
        )

        val rows = arrayOf(
            PracticeRow(R.id.practice_0, R.id.practice_0_name,
                arrayOf(R.id.practice_0_set_0, R.id.practice_0_set_1, R.id.practice_0_set_2)),
            PracticeRow(R.id.practice_1, R.id.practice_1_name,
                arrayOf(R.id.practice_1_set_0, R.id.practice_1_set_1, R.id.practice_1_set_2)),
            PracticeRow(R.id.practice_2, R.id.practice_2_name,
                arrayOf(R.id.practice_2_set_0, R.id.practice_2_set_1, R.id.practice_2_set_2)),
            PracticeRow(R.id.practice_3, R.id.practice_3_name,
                arrayOf(R.id.practice_3_set_0, R.id.practice_3_set_1, R.id.practice_3_set_2)),
            PracticeRow(R.id.practice_4, R.id.practice_4_name,
                arrayOf(R.id.practice_4_set_0, R.id.practice_4_set_1, R.id.practice_4_set_2)),
        )

        for (i in rows.indices) {
            val row = rows[i]
            if (i < count) {
                val name = widgetData.getString("practice_${i}_name", "") ?: ""
                val practiceId = widgetData.getInt("practice_${i}_id", 0)
                val targetSets = widgetData.getInt("practice_${i}_target_sets", 1)
                val completedSets = widgetData.getInt("practice_${i}_completed_sets", 0)
                val allDone = completedSets >= targetSets

                views.setViewVisibility(row.rowId, View.VISIBLE)
                views.setTextViewText(row.nameId, name)
                // Dim name when all sets done
                views.setTextColor(row.nameId, if (allDone) 0xFF777777.toInt() else 0xFFE0E0E0.toInt())

                // Tap practice name → open app to Today tab
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = "OPEN_TODAY"
                    data = Uri.parse("brainapp://today")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openPending = PendingIntent.getActivity(
                    context, 400 + i, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(row.nameId, openPending)

                // Set buttons (up to 3)
                for (s in row.setIds.indices) {
                    if (s < targetSets) {
                        val isDone = (s + 1) <= completedSets
                        views.setViewVisibility(row.setIds[s], View.VISIBLE)
                        views.setImageViewResource(row.setIds[s],
                            if (isDone) R.drawable.ic_check_circle else R.drawable.ic_check_circle_outline)

                        if (practiceId > 0) {
                            // Tapping a set button → background callback to log/undo
                            val setUri = if (isDone) {
                                Uri.parse("brainapp://practice-undo/$practiceId")
                            } else {
                                Uri.parse("brainapp://practice-log/$practiceId")
                            }
                            val setPending = HomeWidgetBackgroundIntent.getBroadcast(context, setUri)
                            views.setOnClickPendingIntent(row.setIds[s], setPending)
                        }
                    } else {
                        views.setViewVisibility(row.setIds[s], View.GONE)
                    }
                }
            } else {
                views.setViewVisibility(row.rowId, View.GONE)
            }
        }

        return views
    }
}
