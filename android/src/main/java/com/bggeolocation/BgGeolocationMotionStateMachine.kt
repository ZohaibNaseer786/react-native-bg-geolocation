package com.bggeolocation

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.modules.core.DeviceEventManagerModule

/**
 * Motion state machine — detects moving ↔ stationary transitions.
 *
 * Algorithm (mirrors the original library's logic):
 *
 * MOVING state:
 *   - Start a "still timer" when GPS speed drops below SPEED_THRESHOLD AND
 *     the activity recognition says STILL.
 *   - If the still timer reaches stopTimeout → transition to STATIONARY.
 *   - Any movement (speed or activity) resets the still timer.
 *
 * STATIONARY state:
 *   - Any movement detected (speed spike or moving activity) → MOVING immediately.
 *
 * The state is persisted in SharedPreferences, so it survives kill/relaunch.
 */
object BgGeolocationMotionStateMachine {

  private const val TAG = "BgGeoMotion"

  // GPS speed threshold below which we consider the device potentially stationary (m/s).
  // ~2 km/h — low enough to catch a slow walk but ignore GPS jitter.
  private const val SPEED_THRESHOLD_MS = 0.56f

  private const val KEY_STILL_SINCE     = "motion_still_since"
  private const val KEY_INITIALIZED     = "motion_initialized"

  fun update(context: Context, location: Location, prefs: SharedPreferences) {
    val stopTimeoutMs = prefs.getLong("stopTimeout", 60L) * 1000L

    // Read current state
    val currentlyMoving = prefs.getBoolean(
      BgGeolocationActivityRecognitionReceiver.KEY_IS_MOVING, false
    )
    val initialized = prefs.contains(KEY_INITIALIZED)

    // Signals from both GPS and activity recognition
    val speed      = location.speed
    val gpsMoving  = speed > SPEED_THRESHOLD_MS
    val actMoving  = BgGeolocationActivityRecognitionReceiver.readIsMoving(context)

    Log.d("BgGeoTest",
      "[MOTION STATE] speed=${String.format("%.2f", speed)}m/s " +
        "gps=${if (gpsMoving) "MOVING" else "STILL"} " +
        "activity=${if (actMoving) "MOVING" else "STILL"} " +
        "current=${if (currentlyMoving) "MOVING" else "STATIONARY"}"
    )

    if (!initialized) {
      // First location fix — establish initial state
      val initialMoving = gpsMoving || actMoving
      prefs.edit()
        .putBoolean(KEY_INITIALIZED, true)
        .putBoolean(BgGeolocationActivityRecognitionReceiver.KEY_IS_MOVING, initialMoving)
        .putLong(KEY_STILL_SINCE, 0L)
        .apply()
      Log.d("BgGeoTest", "[MOTION STATE] initialized → ${if (initialMoving) "MOVING" else "STATIONARY"}")
      return
    }

    if (currentlyMoving) {
      // ── Currently MOVING — check for stop ────────────────────────────────
      val evidenceOfMovement = gpsMoving || actMoving
      if (!evidenceOfMovement) {
        // Start or continue the still timer
        val stillSince = prefs.getLong(KEY_STILL_SINCE, 0L)
        if (stillSince == 0L) {
          prefs.edit().putLong(KEY_STILL_SINCE, System.currentTimeMillis()).apply()
          Log.d("BgGeoTest", "[MOTION STATE] ⏱ still timer started (stopTimeout=${stopTimeoutMs/1000}s)")
        } else {
          val elapsed = System.currentTimeMillis() - stillSince
          Log.d("BgGeoTest", "[MOTION STATE] still for ${elapsed/1000}s / ${stopTimeoutMs/1000}s")
          if (elapsed >= stopTimeoutMs) {
            Log.d("BgGeoTest", "[MOTION STATE] ⏱ stopTimeout reached → STATIONARY")
            transitionTo(context, prefs, false, location)
          }
        }
      } else {
        // Device is still moving — clear the still timer if it was running
        if (prefs.getLong(KEY_STILL_SINCE, 0L) != 0L) {
          prefs.edit().putLong(KEY_STILL_SINCE, 0L).apply()
          Log.d("BgGeoTest", "[MOTION STATE] still timer reset (movement detected)")
        }
      }
    } else {
      // ── Currently STATIONARY — check for movement ─────────────────────────
      if (gpsMoving || actMoving) {
        Log.d("BgGeoTest", "[MOTION STATE] movement detected → MOVING")
        prefs.edit().putLong(KEY_STILL_SINCE, 0L).apply()
        transitionTo(context, prefs, true, location)
      }
    }
  }

  /**
   * Persist the new moving/stationary state and emit a `motionchange` event.
   */
  private fun transitionTo(
    context: Context,
    prefs: SharedPreferences,
    moving: Boolean,
    location: Location
  ) {
    prefs.edit()
      .putBoolean(BgGeolocationActivityRecognitionReceiver.KEY_IS_MOVING, moving)
      .putLong(KEY_STILL_SINCE, 0L)
      .apply()

    val activityType = BgGeolocationActivityRecognitionReceiver.readActivityType(context)
    val activityConf = BgGeolocationActivityRecognitionReceiver.readActivityConfidence(context)

    Log.d("BgGeoTest",
      "[MOTION STATE] 🔄 motionchange isMoving=$moving " +
        "activity=$activityType (${activityConf}%)"
    )

    val payload = Arguments.createMap().apply {
      putBoolean("isMoving", moving)
      putMap("activity", Arguments.createMap().apply {
        putString("type",       activityType)
        putInt("confidence",    activityConf)
      })
      putMap("location", Arguments.createMap().apply {
        putDouble("latitude",  location.latitude)
        putDouble("longitude", location.longitude)
        putDouble("accuracy",  location.accuracy.toDouble())
      })
    }

    val reactContext = BgGeolocationModule.getReactContext()
    if (reactContext != null) {
      try {
        reactContext
          .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
          ?.emit("motionchange", payload)
        Log.d("BgGeoTest", "[MOTION STATE] motionchange → JS")
      } catch (e: Exception) {
        Log.w(TAG, "emit motionchange failed: ${e.message}")
      }
    } else {
      val headlessMap = Arguments.createMap().apply {
        putBoolean("isMoving",    moving)
        putString("activityType", activityType)
        putInt("confidence",      activityConf)
      }
      BgGeolocationHeadlessTask.onEvent(context, "motionchange", headlessMap)
      Log.d("BgGeoTest", "[MOTION STATE] motionchange → HeadlessTask (app killed)")
    }
  }
}
