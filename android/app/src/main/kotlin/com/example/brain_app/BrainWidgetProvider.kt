package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
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
            val views = RemoteViews(context.packageName, R.layout.brain_widget)
            val count = widgetData.getInt("action_count", 0)

            // Entry rows
            val entryIds = arrayOf(
                Triple(R.id.entry_0, R.id.entry_0_title, R.id.entry_0_due),
                Triple(R.id.entry_1, R.id.entry_1_title, R.id.entry_1_due),
                Triple(R.id.entry_2, R.id.entry_2_title, R.id.entry_2_due),
                Triple(R.id.entry_3, R.id.entry_3_title, R.id.entry_3_due),
            )

            for (i in 0 until 4) {
                val (rowId, titleId, dueId) = entryIds[i]
                if (i < count) {
                    val title = widgetData.getString("entry_${i}_title", "") ?: ""
                    val due = widgetData.getString("entry_${i}_due", "") ?: ""
                    val entryId = widgetData.getString("entry_${i}_id", "") ?: ""

                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(titleId, title)
                    views.setTextViewText(dueId, due)

                    // Tap entry to open it
                    if (entryId.isNotEmpty()) {
                        val openIntent = Intent(context, MainActivity::class.java).apply {
                            action = "OPEN_ENTRY"
                            data = Uri.parse("brainapp://entry/$entryId")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        val pendingIntent = PendingIntent.getActivity(
                            context, i, openIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        views.setOnClickPendingIntent(rowId, pendingIntent)
                    }
                } else {
                    views.setViewVisibility(rowId, View.GONE)
                }
            }

            // Empty state
            views.setViewVisibility(
                R.id.empty_text,
                if (count > 0) View.GONE else View.VISIBLE
            )

            // Mic button — opens app for voice capture
            val micIntent = Intent(context, MainActivity::class.java).apply {
                action = "VOICE_CAPTURE"
                data = Uri.parse("brainapp://voice")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val micPending = PendingIntent.getActivity(
                context, 100, micIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_mic, micPending)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
