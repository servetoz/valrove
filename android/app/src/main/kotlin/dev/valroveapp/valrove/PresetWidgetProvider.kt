package dev.valroveapp.valrove

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget with the first presets and a Dock button. The app writes
 * the names and links (see `launchers.dart`); a tap opens Valrove, which then
 * carries out the link.
 */
class PresetWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.preset_widget)
            views.setTextViewText(
                R.id.widget_title,
                widgetData.getString("robot_name", null) ?: context.getString(R.string.app_name),
            )
            views.setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            var shown = 0
            PRESET_VIEWS.forEachIndexed { i, viewId ->
                val name = widgetData.getString("preset_${i}_name", null)
                val link = widgetData.getString("preset_${i}_uri", null)
                if (name != null && link != null) {
                    shown++
                    views.setViewVisibility(viewId, View.VISIBLE)
                    views.setTextViewText(viewId, name)
                    views.setOnClickPendingIntent(viewId, launch(context, link))
                } else {
                    views.setViewVisibility(viewId, View.GONE)
                }
            }
            views.setViewVisibility(R.id.widget_empty, if (shown == 0) View.VISIBLE else View.GONE)
            views.setOnClickPendingIntent(
                R.id.widget_empty,
                launch(context, widgetData.getString("presets_uri", null) ?: "valrove://presets"),
            )

            val dock = widgetData.getString("dock_uri", null)
            views.setViewVisibility(R.id.widget_dock, if (dock != null) View.VISIBLE else View.GONE)
            if (dock != null) views.setOnClickPendingIntent(R.id.widget_dock, launch(context, dock))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun launch(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    private companion object {
        val PRESET_VIEWS = intArrayOf(R.id.widget_preset_0, R.id.widget_preset_1, R.id.widget_preset_2)
    }
}
