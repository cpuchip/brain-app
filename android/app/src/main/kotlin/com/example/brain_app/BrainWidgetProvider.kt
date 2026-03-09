package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import android.app.PendingIntent
import android.content.Intent

class BrainWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            // Build all layouts
            val standardView = buildStandardView(context, widgetData)
            val compactView = buildCompactView(context)
            val miniView = buildMiniView(context)

            // Responsive layout map: launcher picks layout based on widget size
            val viewMapping = mapOf(
                SizeF(110f, 50f) to miniView,        // 2x1
                SizeF(110f, 110f) to compactView,    // 2x2
                SizeF(250f, 110f) to standardView    // 4x2+
            )
            appWidgetManager.updateAppWidget(widgetId, RemoteViews(viewMapping))
        }
    }

    private fun buildCompactView(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.brain_widget_compact)

        // + button → text mode quick-add
        val addIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=text")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPending = PendingIntent.getActivity(
            context, 101, addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_add, addPending)

        // Mic button → voice mode quick-add
        val micIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=voice")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val micPending = PendingIntent.getActivity(
            context, 100, micIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_mic, micPending)

        return views
    }

    private fun buildMiniView(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.brain_widget_mini)

        // Brain icon → launch main app history view
        val brainIntent = Intent(context, MainActivity::class.java).apply {
            action = "REFRESH_WIDGET"
            data = android.net.Uri.parse("brainapp://refresh")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val brainPending = PendingIntent.getActivity(
            context, 103, brainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_brain, brainPending)

        // + button → text mode quick-add
        val addIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=text")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPending = PendingIntent.getActivity(
            context, 101, addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_add, addPending)

        // Mic button → voice mode quick-add
        val micIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=voice")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val micPending = PendingIntent.getActivity(
            context, 100, micIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_mic, micPending)

        return views
    }

    private fun buildStandardView(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.brain_widget)
        val count = widgetData.getInt("action_count", 0)

        data class EntryRow(
            val rowId: Int,
            val checkId: Int,
            val titleId: Int,
            val dueId: Int
        )

        val entryRows = arrayOf(
            EntryRow(R.id.entry_0, R.id.entry_0_check, R.id.entry_0_title, R.id.entry_0_due),
            EntryRow(R.id.entry_1, R.id.entry_1_check, R.id.entry_1_title, R.id.entry_1_due),
            EntryRow(R.id.entry_2, R.id.entry_2_check, R.id.entry_2_title, R.id.entry_2_due),
            EntryRow(R.id.entry_3, R.id.entry_3_check, R.id.entry_3_title, R.id.entry_3_due),
        )

        for (i in 0 until 4) {
            val row = entryRows[i]
            if (i < count) {
                val title = widgetData.getString("entry_${i}_title", "") ?: ""
                val due = widgetData.getString("entry_${i}_due", "") ?: ""
                val entryId = widgetData.getString("entry_${i}_id", "") ?: ""

                views.setViewVisibility(row.rowId, View.VISIBLE)
                views.setTextViewText(row.titleId, title)
                views.setTextViewText(row.dueId, due)

                // Swap checkbox drawable based on done state
                val isDone = widgetData.getBoolean("entry_${i}_done", false)
                views.setImageViewResource(row.checkId,
                    if (isDone) R.drawable.ic_check_circle else R.drawable.ic_check_circle_outline)

                if (entryId.isNotEmpty()) {
                    // Tap title area → open entry for editing
                    val openIntent = Intent(context, MainActivity::class.java).apply {
                        action = "OPEN_ENTRY"
                        data = Uri.parse("brainapp://entry/$entryId")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    val openPending = PendingIntent.getActivity(
                        context, i, openIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(row.titleId, openPending)
                    views.setOnClickPendingIntent(row.dueId, openPending)

                    // Checkbox → mark done via background callback (no app flash)
                    val donePending = HomeWidgetBackgroundIntent.getBroadcast(
                        context, Uri.parse("brainapp://done/$entryId"))
                    views.setOnClickPendingIntent(row.checkId, donePending)
                }
            } else {
                views.setViewVisibility(row.rowId, View.GONE)
            }
        }

        // Empty state
        views.setViewVisibility(
            R.id.empty_text,
            if (count > 0) View.GONE else View.VISIBLE
        )

        // Refresh button — opens main app (triggers data load + widget update)
        val refreshIntent = Intent(context, MainActivity::class.java).apply {
            action = "REFRESH_WIDGET"
            data = Uri.parse("brainapp://refresh")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val refreshPending = PendingIntent.getActivity(
            context, 102, refreshIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_refresh, refreshPending)

        // Mic button — launches transparent quick-add in voice mode
        val micIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=voice")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val micPending = PendingIntent.getActivity(
            context, 100, micIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_mic, micPending)

        // + button — launches transparent quick-add in text mode
        val addIntent = Intent(context, QuickAddActivity::class.java).apply {
            data = Uri.parse("brainapp://quick-add?mode=text")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val addPending = PendingIntent.getActivity(
            context, 101, addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_add, addPending)

        return views
    }
}
