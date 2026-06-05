package com.bggeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Receives activity-recognition updates from Google Play Services.
 *
 * Because the PendingIntent that drives this receiver is owned by the OS, it
 * fires in ALL app states — foreground, background AND after the app is killed.
 *
 * On every update it:
 *   1. Persists the latest {type, confidence, isMoving} to SharedPreferences so
 *      the module / foreground-service can stamp it onto every location.
 *   2. Emits a `motionchange` event when the moving<->stationary state flips:
 *        - to JS via DeviceEventEmitter when the React context is alive
 *        - via the HeadlessTask when the app is killed.
 *
 * Declared in AndroidManifest.xml as a non-exported receiver.
 */
class BgGeolocationActivityRecognitionReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG  = "BgGeoActivity"
    private const val PREFS = "bg_geolocation_prefs"
    const val KEY_ACTIVITY_TYPE = "activity_type"
    const val KEY_ACTIVITY_CONF = "activity_confidence"
    const val KEY_IS_MOVING     = "activity_is_moving"

    /** Map a Play-Services activity to our string + moving flag. */
    fun describe(type: Int): Pair<String, Boolean> = when (type) {
      DetectedActivity.IN_VEHICLE -> "in_vehicle" to true
      DetectedActivity.ON_BICYCLE -> "on_bicycle" to true
      DetectedActivity.ON_FOOT    -> "on_foot" to true
      DetectedActivity.RUNNING    -> "running" to true
      DetectedActivity.WALKING    -> "walking" to true
      DetectedActivity.STILL      -> "still" to false
      DetectedActivity.TILTING    -> "tilting" to false
      else                        -> "unknown" to false
    }

    fun readActivityType(context: Context): String =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString(KEY_ACTIVITY_TYPE, "unknown") ?: "unknown"

    fun readActivityConfidence(context: Context): Int =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getInt(KEY_ACTIVITY_CONF, 0)

    fun readIsMoving(context: Context): Boolean =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_IS_MOVING, false)
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (!ActivityRecognitionResult.hasResult(intent)) return
    val result = ActivityRecognitionResult.extractResult(intent) ?: return

    val mostProbable = result.mostProbableActivity
    val (typeStr, isMoving) = describe(mostProbable.type)
    val confidence = mostProbable.confidence

    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    val wasMoving = prefs.getBoolean(KEY_IS_MOVING, false)
    val hadPrevious = prefs.contains(KEY_IS_MOVING)

    // Persist latest activity so locations can be stamped with it in any state.
    prefs.edit()
      .putString(KEY_ACTIVITY_TYPE, typeStr)
      .putInt(KEY_ACTIVITY_CONF, confidence)
      .putBoolean(KEY_IS_MOVING, isMoving)
      .apply()

    Log.d("BgGeoTest", "[ACTIVITY] $typeStr (moving=$isMoving conf=$confidence)")

    // Only emit motionchange on an actual transition.
    if (hadPrevious && wasMoving == isMoving) return

    val payload = Arguments.createMap().apply {
      putBoolean("isMoving", isMoving)
      putMap("activity", Arguments.createMap().apply {
        putString("type", typeStr)
        putInt("confidence", confidence)
      })
    }

    val reactContext = BgGeolocationModule.getReactContext()

    if (reactContext != null) {
      // App alive — emit straight to JS.
      try {
        reactContext
          .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
          ?.emit("motionchange", payload)
        Log.d("BgGeoTest", "[ACTIVITY] motionchange → JS (isMoving=$isMoving)")
      } catch (e: Exception) {
        Log.w(TAG, "emit motionchange failed: ${e.message}")
      }
    } else {
      // App killed — route through the headless task.
      val headlessMap = Arguments.createMap().apply {
        putBoolean("isMoving", isMoving)
        putString("activityType", typeStr)
        putInt("confidence", confidence)
      }
      BgGeolocationHeadlessTask.onEvent(context.applicationContext, "motionchange", headlessMap)
      Log.d("BgGeoTest", "[ACTIVITY] motionchange → HEADLESS (isMoving=$isMoving)")
    }
  }
}
