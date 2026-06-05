package com.bggeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the foreground location service after a device reboot if tracking was
 * active before. The service re-requests FusedLocation updates on start, so
 * tracking resumes automatically.
 *
 * Registered in AndroidManifest for BOOT_COMPLETED and QUICKBOOT_POWERON.
 */
class BgGeolocationBootReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG  = "BgGeoBootReceiver"
    private const val PREF = "bg_geolocation_prefs"
    private const val KEY_ENABLED = "tracking_enabled"

    fun setTrackingEnabled(context: Context, enabled: Boolean) {
      context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        .edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun isTrackingEnabled(context: Context): Boolean {
      return context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        .getBoolean(KEY_ENABLED, false)
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    if (action != Intent.ACTION_BOOT_COMPLETED &&
        action != "android.intent.action.QUICKBOOT_POWERON") return

    if (!isTrackingEnabled(context)) return

    Log.d(TAG, "Boot detected — restarting location foreground service")
    // The service re-requests FusedLocation updates on start.
    BgGeolocationForegroundService.start(context)
  }
}
