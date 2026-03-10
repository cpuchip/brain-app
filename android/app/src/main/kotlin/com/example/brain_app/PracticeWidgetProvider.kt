package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
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
            val views = buildPracticeView(context, widgetData, widgetId)
            appWidgetManager.updateAppWidget(widgetId, views)
            // Trigger RemoteViewsFactory.onDataSetChanged()
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.practice_list)
        }
    }

    private fun buildPracticeView(context: Context, widgetData: SharedPreferences, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.practice_widget)

        // Per-instance filter (fallback to legacy global key, then "All")
        val filter = widgetData.getString("practice_filter_$widgetId", null)
            ?: widgetData.getString("practice_filter", "All")
            ?: "All"

        // Header: category name (tappable → cycle filter for THIS instance)
        views.setTextViewText(R.id.practice_category, if (filter == "All") "All Practices" else filter)

        val filterPending = HomeWidgetBackgroundIntent.getBroadcast(
            context, Uri.parse("brainapp://practice-cycle-filter/$widgetId"))
        views.setOnClickPendingIntent(R.id.practice_category, filterPending)

        // Read ALL practices and filter locally
        val totalCount = widgetData.getInt("all_practice_count", 0)
        var filteredCount = 0
        var dueCount = 0
        var dueCompletedCount = 0
        for (i in 0 until totalCount) {
            val cat = widgetData.getString("all_practice_${i}_category", "") ?: ""
            if (filter != "All" && cat != filter) continue
            filteredCount++
            val isDue = widgetData.getBoolean("all_practice_${i}_is_due", true)
            if (!isDue) continue  // not-due scheduled items don't count in progress
            dueCount++
            val targetSets = widgetData.getInt("all_practice_${i}_target_sets", 1)
            val completedSets = widgetData.getInt("all_practice_${i}_completed_sets", 0)
            if (completedSets >= targetSets) dueCompletedCount++
        }

        // Progress text — shows due items only
        views.setTextViewText(R.id.practice_progress, "$dueCompletedCount/$dueCount")

        // Empty state vs list (show list if any practices match filter, including not-due)
        if (filteredCount > 0) {
            views.setViewVisibility(R.id.practice_empty, View.GONE)
            views.setViewVisibility(R.id.practice_list, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.practice_empty, View.VISIBLE)
            views.setViewVisibility(R.id.practice_list, View.GONE)
        }

        // Set up ListView adapter — unique URI per widget so Android creates separate factories
        val serviceIntent = Intent(context, PracticeWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            data = Uri.parse("practicewidget://instance/$widgetId")
        }
        views.setRemoteAdapter(R.id.practice_list, serviceIntent)

        // Pending intent template for list item clicks (must be mutable for fill-in)
        val templateIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val templatePending = PendingIntent.getBroadcast(context, 500 + widgetId, templateIntent, flags)
        views.setPendingIntentTemplate(R.id.practice_list, templatePending)

        // + button → launches transparent quick-add practice overlay
        val addIntent = Intent(context, QuickAddPracticeActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add-practice")
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPending = PendingIntent.getActivity(
            context, 700 + widgetId, addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.practice_add, addPending)

        return views
    }
}
