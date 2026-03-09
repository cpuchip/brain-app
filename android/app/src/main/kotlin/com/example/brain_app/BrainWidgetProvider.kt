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
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
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
            // Trigger RemoteViewsFactory.onDataSetChanged()
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.entry_list)
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

        // Brain icon → background refresh (no app flash)
        val brainPending = HomeWidgetBackgroundIntent.getBroadcast(
            context, Uri.parse("brainapp://refresh"))
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

        // Empty state vs list
        if (count > 0) {
            views.setViewVisibility(R.id.empty_text, View.GONE)
            views.setViewVisibility(R.id.entry_list, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.empty_text, View.VISIBLE)
            views.setViewVisibility(R.id.entry_list, View.GONE)
        }

        // Set up ListView adapter
        val serviceIntent = Intent(context, BrainWidgetService::class.java)
        views.setRemoteAdapter(R.id.entry_list, serviceIntent)

        // Pending intent template for list item clicks (must be mutable for fill-in)
        val templateIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java)
        val pendingFlags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val templatePending = PendingIntent.getBroadcast(context, 600, templateIntent, pendingFlags)
        views.setPendingIntentTemplate(R.id.entry_list, templatePending)

        // Refresh button — background callback (no app flash)
        val refreshPending = HomeWidgetBackgroundIntent.getBroadcast(
            context, Uri.parse("brainapp://refresh"))
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
