package com.example.brain_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class BrainWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return BrainViewsFactory(applicationContext)
    }
}

class BrainViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private data class EntryItem(
        val id: String,
        val title: String,
        val due: String,
        val isDone: Boolean
    )

    private var items = listOf<EntryItem>()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val count = prefs.getInt("action_count", 0)
        items = (0 until count).map { i ->
            EntryItem(
                id = prefs.getString("entry_${i}_id", "") ?: "",
                title = prefs.getString("entry_${i}_title", "") ?: "",
                due = prefs.getString("entry_${i}_due", "") ?: "",
                isDone = prefs.getBoolean("entry_${i}_done", false)
            )
        }
    }

    override fun getCount() = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= items.size) {
            return RemoteViews(context.packageName, R.layout.brain_widget_item)
        }
        val item = items[position]
        val views = RemoteViews(context.packageName, R.layout.brain_widget_item)

        views.setTextViewText(R.id.entry_item_title, item.title)
        views.setTextViewText(R.id.entry_item_due, item.due)
        views.setImageViewResource(
            R.id.entry_item_check,
            if (item.isDone) R.drawable.ic_check_circle else R.drawable.ic_check_circle_outline
        )

        // Fill-in intent for checkbox: mark done via background callback
        if (item.id.isNotEmpty()) {
            views.setOnClickFillInIntent(
                R.id.entry_item_check,
                Intent().apply { data = Uri.parse("brainapp://done/${item.id}") }
            )
            // Tap title → open entry
            views.setOnClickFillInIntent(
                R.id.entry_item_title,
                Intent().apply {
                    action = "OPEN_ENTRY"
                    data = Uri.parse("brainapp://entry/${item.id}")
                }
            )
        }

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = false
    override fun onDestroy() {}
}
