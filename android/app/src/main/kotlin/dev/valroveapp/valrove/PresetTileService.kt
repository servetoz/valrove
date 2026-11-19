package dev.valroveapp.valrove

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Quick settings tile that starts the first preset (it opens Valrove, which
 * starts the preset). Reads the same data as [PresetWidgetProvider].
 */
class PresetTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val name = HomeWidgetPlugin.getData(this).getString("preset_0_name", null)
        tile.label = name ?: getString(R.string.tile_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(if (name != null) R.string.tile_start else R.string.tile_empty)
        }
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val data = HomeWidgetPlugin.getData(this)
        val link = data.getString("preset_0_uri", null) ?: data.getString("presets_uri", null) ?: "valrove://presets"
        if (isLocked) unlockAndRun { open(link) } else open(link)
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun open(link: String) {
        val uri = Uri.parse(link)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(HomeWidgetLaunchIntent.getActivity(this, MainActivity::class.java, uri))
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
