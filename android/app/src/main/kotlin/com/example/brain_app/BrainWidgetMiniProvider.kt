package com.example.brain_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import android.app.PendingIntent
import android.content.Intent

class BrainWidgetMiniProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.brain_widget_mini)

            // Brain icon → launch main app
            val brainIntent = Intent(context, MainActivity::class.java).apply {
                action = "REFRESH_WIDGET"
                data = Uri.parse("brainapp://refresh")
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

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
