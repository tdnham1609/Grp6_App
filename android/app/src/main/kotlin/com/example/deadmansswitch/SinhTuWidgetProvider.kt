package com.example.deadmansswitch

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class SinhTuWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sinhtu_widget).apply {
                val status = widgetData.getString("widget_status", "Chưa có lịch xác nhận")
                    ?: "Chưa có lịch xác nhận"
                val lastCheckIn = widgetData.getString("widget_last_checkin", "") ?: ""

                setTextViewText(R.id.widget_status, status)
                setTextViewText(R.id.widget_last_checkin, lastCheckIn)

                val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("sinhtu://widget/open"),
                )
                setOnClickPendingIntent(R.id.widget_container, openAppIntent)

                val checkInIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("sinhtu://widget/checkin"),
                )
                setOnClickPendingIntent(R.id.widget_checkin_button, checkInIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
