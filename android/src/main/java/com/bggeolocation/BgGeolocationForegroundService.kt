package com.bggeolocation

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.google.android.gms.location.*
import com.google.android.gms.tasks.CancellationTokenSource
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * BgGeolocationForegroundService
 *
 * The SINGLE active location source for all states.
 *
 * Because it runs as a foreground service with foregroundServiceType="location"
 * AND actively requests FusedLocation updates, Android grants it continuous
 * high-accuracy location in the background and after the app is killed (this is
 * what makes the iOS-style blue location indicator appear). START_STICKY +
 * onTaskRemoved(AlarmManager) make it survive swipe-kill.
 *
 * On each fresh location:
 *   1. Run the motion state machine (moving/stationary).
 *   2. Stamp the latest activity.
 *   3. Persist to disk (getLocations works after relaunch).
 *   4. Deliver:
 *        - React alive  → emit "location" to JS (foreground/background)
 *        - App killed    → fire the HeadlessTask (JS connects socket + sends)
 */
class BgGeolocationForegroundService : Service() {

  companion object {
    const val CHANNEL_ID   = "bg_geolocation_channel"
    const val NOTIF_ID     = 1001
    const val ACTION_START = "com.bggeolocation.START"
    const val ACTION_STOP  = "com.bggeolocation.STOP"
    const val EXTRA_TITLE  = "notif_title"
    const val EXTRA_TEXT   = "notif_text"
    private const val TAG  = "BgGeoService"

    fun start(context: Context, title: String = "BG Geolocation", text: String = "Tracking location") {
      val intent = Intent(context, BgGeolocationForegroundService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_TITLE, title)
        putExtra(EXTRA_TEXT, text)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.startService(
        Intent(context, BgGeolocationForegroundService::class.java).apply {
          action = ACTION_STOP
        }
      )
    }
  }

  private lateinit var fusedClient: FusedLocationProviderClient
  private var locationCallback: LocationCallback? = null     // continuous → keeps the OS location indicator
  private var lastContinuous: Location? = null               // fallback for the periodic fetch
  private var periodHandler: Handler? = null                 // periodic FRESH-fix timer
  private var periodRunnable: Runnable? = null
  private var periodMs: Long = 60_000L

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    createNotificationChannel()
    fusedClient = LocationServices.getFusedLocationProviderClient(this)
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_STOP -> {
        Log.d(TAG, "Stopping foreground service")
        stopLocationUpdates()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        return START_NOT_STICKY
      }
      else -> {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "BG Geolocation"
        val text  = intent?.getStringExtra(EXTRA_TEXT)  ?: "Tracking location"
        Log.d(TAG, "Starting foreground service + location updates")
        // startForeground() MUST succeed and be called promptly — otherwise
        // Android 12+ throws ForegroundServiceDidNotStartInTimeException and
        // fatally crashes the app. buildNotification() is guaranteed not to throw.
        try {
          startForeground(NOTIF_ID, buildNotification(title, text))
        } catch (e: Exception) {
          Log.e(TAG, "startForeground failed: ${e.message}", e)
          stopSelf()
          return START_NOT_STICKY
        }
        // Location updates are started separately — a failure here must NOT
        // prevent startForeground above from having run.
        try {
          startLocationUpdates()
        } catch (e: Exception) {
          Log.e(TAG, "startLocationUpdates failed: ${e.message}", e)
        }
      }
    }
    return START_STICKY
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    Log.d(TAG, "App killed — scheduling service restart")
    val restartIntent = Intent(applicationContext, BgGeolocationForegroundService::class.java).apply {
      action = ACTION_START
    }
    val pending = PendingIntent.getService(
      this, 1, restartIntent,
      PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
    )
    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    alarmManager.set(
      AlarmManager.ELAPSED_REALTIME,
      android.os.SystemClock.elapsedRealtime() + 1000,
      pending
    )
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy() {
    stopLocationUpdates()
    super.onDestroy()
  }

  // ─── Active location updates ────────────────────────────────────────────────
  //
  // TWO mechanisms run together:
  //
  //   1. Continuous requestLocationUpdates — keeps the OS location indicator
  //      (blue dot) on and caches the most recent fix. It does NOT deliver.
  //
  //   2. A periodic timer (period = trackingPeriodMs) that calls
  //      getCurrentLocation(PRIORITY_HIGH_ACCURACY) — this FORCES a brand-new
  //      fix every period (never a cached one) and is the single delivery point.
  //      getCurrentLocation bypasses the background throttling that makes
  //      continuous updates return stale locations after the app is killed.
  //
  // The timer runs on the service's main looper. Because the service is
  // START_STICKY it stays alive after kill, so fresh fixes keep flowing.

  @SuppressLint("MissingPermission")
  private fun startLocationUpdates() {
    if (!hasLocationPermission()) {
      Log.w(TAG, "Cannot start location updates: permission not granted")
      return
    }

    val prefs      = getSharedPreferences("bg_geolocation_prefs", Context.MODE_PRIVATE)
    periodMs       = prefs.getLong("trackingPeriodMs", 60_000L).coerceAtLeast(1_000L)
    val distFilter = prefs.getFloat("distanceFilter", 0f)

    // 1. Continuous updates — indicator + cache only (no delivery).
    val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, periodMs)
      .setMinUpdateDistanceMeters(distFilter)
      .setWaitForAccurateLocation(false)
      .build()
    locationCallback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        result.lastLocation?.let { lastContinuous = it }
      }
    }
    fusedClient.requestLocationUpdates(request, locationCallback!!, Looper.getMainLooper())

    // 2. Periodic FRESH-fix timer — the delivery point.
    periodHandler = Handler(Looper.getMainLooper())
    periodRunnable = object : Runnable {
      override fun run() {
        fetchFreshLocation(prefs)
        periodHandler?.postDelayed(this, periodMs)
      }
    }
    // First fetch immediately, then every period.
    periodHandler?.post(periodRunnable!!)

    Log.d(TAG, "Tracking started — fresh fix every ${periodMs}ms (distFilter=${distFilter}m)")
  }

  /** Force a brand-new high-accuracy fix and deliver it. */
  @SuppressLint("MissingPermission")
  private fun fetchFreshLocation(prefs: SharedPreferences) {
    if (!hasLocationPermission()) return
    val cts = CancellationTokenSource()
    fusedClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token)
      .addOnSuccessListener { fresh ->
        val location = fresh ?: lastContinuous
        if (location != null) {
          Log.d("BgGeoTest", "[SERVICE] 🛰️ fresh fix acquired (fromCache=${fresh == null})")
          handleLocation(prefs, location)
        } else {
          Log.w("BgGeoTest", "[SERVICE] getCurrentLocation returned null and no cache")
        }
      }
      .addOnFailureListener { e ->
        Log.w("BgGeoTest", "[SERVICE] getCurrentLocation failed: ${e.message}")
        lastContinuous?.let { handleLocation(prefs, it) }
      }
  }

  private fun stopLocationUpdates() {
    locationCallback?.let { if (::fusedClient.isInitialized) fusedClient.removeLocationUpdates(it) }
    locationCallback = null
    periodRunnable?.let { periodHandler?.removeCallbacks(it) }
    periodRunnable = null
    periodHandler = null
  }

  /** Process one fresh location fix. */
  private fun handleLocation(prefs: SharedPreferences, location: Location) {
    val alive = BgGeolocationModule.getReactContext() != null
    val state = if (alive) "ALIVE" else "KILLED"

    // 1. Motion state machine (moving/stationary). Emits motionchange on transition.
    BgGeolocationMotionStateMachine.update(applicationContext, location, prefs)

    // 2. Latest activity (persisted by the activity-recognition receiver)
    val activityType = BgGeolocationActivityRecognitionReceiver.readActivityType(applicationContext)
    val activityConf = BgGeolocationActivityRecognitionReceiver.readActivityConfidence(applicationContext)
    val isMoving     = BgGeolocationActivityRecognitionReceiver.readIsMoving(applicationContext)

    val uuid      = UUID.randomUUID().toString()
    val timestamp = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
      .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
      .format(java.util.Date(location.time))

    Log.d("BgGeoTest",
      "[SERVICE/$state] 📍 lat=${location.latitude} lng=${location.longitude} " +
        "acc=${location.accuracy}m speed=${location.speed} moving=$isMoving activity=$activityType"
    )

    val map = buildLocationMap(location, uuid, timestamp, isMoving, activityType, activityConf)

    // 3. Persist to disk (single writer → getLocations works after relaunch)
    persistLocationToDisk(prefs, map)

    // 4. Deliver
    if (alive) {
      // Emit to JS — foreground & background. The module's JS listeners receive it.
      try {
        BgGeolocationModule.getReactContext()
          ?.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
          ?.emit("location", map)
      } catch (e: Exception) {
        Log.w(TAG, "emit location failed: ${e.message}")
      }
    } else {
      // Kill state → HeadlessTask (JS connects socket + sends)
      BgGeolocationHeadlessTask.onLocation(applicationContext, map)
    }
  }

  private fun buildLocationMap(
    location: Location, uuid: String, timestamp: String,
    isMoving: Boolean, activityType: String, activityConf: Int
  ): WritableMap = Arguments.createMap().apply {
    putString("uuid", uuid)
    putString("timestamp", timestamp)
    putMap("coords", Arguments.createMap().apply {
      putDouble("latitude", location.latitude)
      putDouble("longitude", location.longitude)
      putDouble("accuracy", location.accuracy.toDouble())
      putDouble("altitude", location.altitude)
      putDouble("altitudeAccuracy",
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
          location.verticalAccuracyMeters.toDouble() else -1.0)
      putDouble("heading", location.bearing.toDouble())
      putDouble("speed", location.speed.toDouble())
    })
    putBoolean("is_moving", isMoving)
    putDouble("odometer", 0.0)
    putMap("activity", Arguments.createMap().apply {
      putString("type", activityType)
      putInt("confidence", activityConf)
    })
    putMap("battery", Arguments.createMap().apply {
      putDouble("level", -1.0)
      putBoolean("is_charging", false)
    })
  }

  private fun persistLocationToDisk(prefs: SharedPreferences, map: WritableMap) {
    try {
      val arr = JSONArray(prefs.getString("persistedLocations", "[]") ?: "[]")
      arr.put(JSONObject(map.toHashMap()))
      while (arr.length() > 500) arr.remove(0)
      prefs.edit().putString("persistedLocations", arr.toString()).apply()
    } catch (e: Exception) {
      Log.w(TAG, "persistLocationToDisk failed: ${e.message}")
    }
  }

  private fun hasLocationPermission(): Boolean {
    return ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED ||
      ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED
  }

  // ─── Notification ─────────────────────────────────────────────────────────

  private fun buildNotification(title: String, text: String): Notification {
    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
    val pendingIntent = if (launchIntent != null) {
      PendingIntent.getActivity(this, 0, launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    } else null

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setContentTitle(title)
      .setContentText(text)
      .setSmallIcon(resolveSmallIcon())
      .setOngoing(true)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setContentIntent(pendingIntent)
      .build()
  }

  /**
   * Pick a small-icon that is guaranteed to be a valid, renderable resource.
   * A vector drawable can fail as a notification small-icon on some OEM ROMs and
   * cause startForeground() to throw "Bad notification" → fatal FGS crash.
   * The app's own launcher icon is always present and safe.
   */
  private fun resolveSmallIcon(): Int {
    val appIcon = try { applicationInfo.icon } catch (e: Exception) { 0 }
    if (appIcon != 0) return appIcon
    return android.R.drawable.ic_menu_mylocation
  }

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        CHANNEL_ID, "Background Location", NotificationManager.IMPORTANCE_LOW
      ).apply {
        description = "Keeps location tracking active in the background"
        setShowBadge(false)
      }
      getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
  }
}
