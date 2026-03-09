package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
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
        val targetSets: Int,
        val completedSets: Int
    )

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
        items = (0 until totalCount).mapNotNull { i ->
            val cat = prefs.getString("all_practice_${i}_category", "") ?: ""
            if (filter != "All" && cat != filter) return@mapNotNull null
            PracticeItem(
                id = prefs.getInt("all_practice_${i}_id", 0),
                name = prefs.getString("all_practice_${i}_name", "") ?: "",
                targetSets = prefs.getInt("all_practice_${i}_target_sets", 1),
                completedSets = prefs.getInt("all_practice_${i}_completed_sets", 0)
            )
        }
    }

    override fun getCount() = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= items.size) {
            return RemoteViews(context.packageName, R.layout.practice_widget_item)
        }
        val item = items[position]
        val views = RemoteViews(context.packageName, R.layout.practice_widget_item)

        views.setTextViewText(R.id.practice_item_name, item.name)
        val allDone = item.completedSets >= item.targetSets
        views.setTextColor(
            R.id.practice_item_name,
            if (allDone) 0xFF777777.toInt() else 0xFFE0E0E0.toInt()
        )

        val setIds = arrayOf(
            R.id.practice_item_set_0,
            R.id.practice_item_set_1,
            R.id.practice_item_set_2
        )

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

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = items.getOrNull(position)?.id?.toLong() ?: position.toLong()
    override fun hasStableIds() = true
    override fun onDestroy() {}
}
