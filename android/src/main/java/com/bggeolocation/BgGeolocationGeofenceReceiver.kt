package com.bggeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/**
 * Receives geofence transition broadcasts from the GeofencingClient and forwards
 * ENTER / EXIT / DWELL events to a registered callback in BgGeolocationModule.
 *
 * This fires even when the app is in the background or killed, because the
 * PendingIntent is owned by the OS.
 *
 * Declared in AndroidManifest.xml as a non-exported receiver.
 */
class BgGeolocationGeofenceReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG = "BgGeoGeofence"

    @Volatile
    private var callback: ((identifier: String, action: String) -> Unit)? = null

    fun setCallback(cb: (identifier: String, action: String) -> Unit) {
      callback = cb
    }

    fun clearCallback() {
      callback = null
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    val event = GeofencingEvent.fromIntent(intent) ?: return
    if (event.hasError()) {
      Log.w(TAG, "Geofence error code: ${event.errorCode}")
      return
    }

    val action = when (event.geofenceTransition) {
      Geofence.GEOFENCE_TRANSITION_ENTER -> "ENTER"
      Geofence.GEOFENCE_TRANSITION_EXIT  -> "EXIT"
      Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
      else -> return
    }

    event.triggeringGeofences?.forEach { geofence ->
      Log.d(TAG, "Geofence $action: ${geofence.requestId}")
      callback?.invoke(geofence.requestId, action)
    }
  }
}
