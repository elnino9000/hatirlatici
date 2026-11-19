package com.hatirlatici.hatirlatici

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class HizliWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val i = Intent(context, MainActivity::class.java).apply {
                action = "com.hatirlatici.SESLI"
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val pi = PendingIntent.getActivity(
                context, 0, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val v = RemoteViews(context.packageName, R.layout.widget_hizli)
            v.setOnClickPendingIntent(R.id.widget_kok, pi)
            mgr.updateAppWidget(id, v)
        }
    }
}
