package com.hatirlatici.hatirlatici

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

object NotVeri {
    private const val DOSYA = "FlutterSharedPreferences"
    private const val ANAHTAR = "flutter.notlar_v1"

    private class Kayit(val id: Long, val text: String, val created: Long, val pin: Boolean)

    fun oku(ctx: Context): List<Pair<Long, String>> {
        val raw = ctx.getSharedPreferences(DOSYA, Context.MODE_PRIVATE)
            .getString(ANAHTAR, null) ?: return emptyList()
        val liste = ArrayList<Kayit>()
        try {
            val a = JSONArray(raw)
            for (i in 0 until a.length()) {
                val o = a.getJSONObject(i)
                if (o.optBoolean("done", false)) continue
                liste.add(
                    Kayit(
                        o.getLong("id"),
                        o.getString("text"),
                        o.optLong("createdMs", 0L),
                        o.optBoolean("pin", false)
                    )
                )
            }
        } catch (e: Exception) {
            return emptyList()
        }
        val sirali = liste.sortedWith(
            compareByDescending<Kayit> { it.pin }.thenByDescending { it.created }
        )
        return sirali.map { Pair(it.id, if (it.pin) "\uD83D\uDCCC " + it.text else it.text) }
    }

    fun bitir(ctx: Context, id: Long) {
        val sp = ctx.getSharedPreferences(DOSYA, Context.MODE_PRIVATE)
        val raw = sp.getString(ANAHTAR, null) ?: return
        try {
            val a = JSONArray(raw)
            val yeni = JSONArray()
            for (i in 0 until a.length()) {
                val o: JSONObject = a.getJSONObject(i)
                if (o.getLong("id") == id) {
                    o.put("done", true)
                    o.put("doneMs", System.currentTimeMillis())
                }
                yeni.put(o)
            }
            sp.edit().putString(ANAHTAR, yeni.toString()).commit()
        } catch (e: Exception) {
        }
    }
}

class NotWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) guncelle(context, mgr, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.hatirlatici.NOT_BITTI") {
            val id = intent.getLongExtra("id", -1L)
            if (id >= 0) NotVeri.bitir(context, id)
            yenile(context)
        }
    }

    companion object {
        fun yenile(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            val ids = m.getAppWidgetIds(ComponentName(context, NotWidget::class.java))
            m.notifyAppWidgetViewDataChanged(ids, R.id.widget_liste)
        }

        fun guncelle(context: Context, mgr: AppWidgetManager, id: Int) {
            val v = RemoteViews(context.packageName, R.layout.widget_not)

            val servis = Intent(context, NotServis::class.java)
            servis.data = Uri.parse(servis.toUri(Intent.URI_INTENT_SCHEME))
            v.setRemoteAdapter(R.id.widget_liste, servis)
            v.setEmptyView(R.id.widget_liste, R.id.widget_bos)

            val sablon = Intent(context, NotWidget::class.java).apply {
                action = "com.hatirlatici.NOT_BITTI"
            }
            val sablonPi = PendingIntent.getBroadcast(
                context, 1, sablon,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            v.setPendingIntentTemplate(R.id.widget_liste, sablonPi)

            val mic = Intent(context, MainActivity::class.java).apply {
                action = "com.hatirlatici.SESLI"
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val micPi = PendingIntent.getActivity(
                context, 2, mic,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            v.setOnClickPendingIntent(R.id.widget_mic, micPi)

            val ac = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val acPi = PendingIntent.getActivity(
                context, 3, ac,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            v.setOnClickPendingIntent(R.id.widget_baslik, acPi)

            mgr.updateAppWidget(id, v)
        }
    }
}
