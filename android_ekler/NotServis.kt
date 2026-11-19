package com.hatirlatici.hatirlatici

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class NotServis : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NotFabrika(applicationContext)
}

class NotFabrika(private val ctx: Context) : RemoteViewsService.RemoteViewsFactory {
    private var liste: List<Pair<Long, String>> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        liste = NotVeri.oku(ctx)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = liste.size

    override fun getViewAt(position: Int): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.widget_not_satir)
        if (position >= liste.size) return v
        val (id, metin) = liste[position]
        v.setTextViewText(R.id.satir_metin, metin)
        v.setOnClickFillInIntent(R.id.satir_kok, Intent())
        return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        if (position < liste.size) liste[position].first else position.toLong()

    override fun hasStableIds(): Boolean = true
}
