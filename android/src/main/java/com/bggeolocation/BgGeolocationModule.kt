package com.bggeolocation

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.common.LifecycleState
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit

class BgGeolocationModule(reactContext: ReactApplicationContext) :
  NativeBgGeolocationSpec(reactContext) {

  companion object {
    const val NAME = NativeBgGeolocationSpec.NAME
    const val TEST_TAG = "BgGeoTest"

    /**
     * True while the JS bridge / React context is alive. The ForegroundService
     * uses this to decide whether to dispatch to the HeadlessTask: when the app
     * is alive the module's own listener already emits the event, so the service
     * must NOT also fire a headless task (that would double-process each location).
     * When the app is killed this is false (fresh process), so the service routes
     * locations through the headless task.
     */
    @Volatile
    @JvmStatic
    var isReactContextAlive = false

    @Volatile
    private var currentReactContext: ReactApplicationContext? = null

    @JvmStatic
    fun getReactContext(): ReactApplicationContext? = currentReactContext
  }

  // ─── Location (Fused) ─────────────────────────────────────────────────────
  // Used only for getCurrentPosition / watchPosition. Continuous tracking is
  // owned by the ForegroundService.
  private lateinit var fusedClient: FusedLocationProviderClient
  private var watchPositionCallback: LocationCallback? = null

  // ─── Activity Recognition ─────────────────────────────────────────────────
  private lateinit var activityRecognitionClient: ActivityRecognitionClient
  private var activityPendingIntent: android.app.PendingIntent? = null

  // ─── Geofencing ─────────────────────────────────────────────────────────────
  private var geofencingClient: GeofencingClient? = null
  private var geofencePendingIntent: android.app.PendingIntent? = null

  // ─── Heartbeat ──────────────────────────────────────────────────────────────
  private var heartbeatHandler: Handler? = null
  private var heartbeatRunnable: Runnable? = null

  // ─── State ────────────────────────────────────────────────────────────────
  private var isTracking = false
  private var isMoving = false
  private var config = JSONObject()
  private val locationStore = mutableListOf<WritableMap>()
  private val geofenceStore = mutableListOf<WritableMap>()
  private var odometer = 0.0
  private var lastLocation: Location? = null
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

  // ─── Disk persistence ─────────────────────────────────────────────────────
  private val prefs by lazy {
    reactApplicationContext.getSharedPreferences("bg_geolocation_prefs", Context.MODE_PRIVATE)
  }
  private val maxPersistedLocations = 500

  // ─── HTTP ──────────────────────────────────────────────────────────────────
  private val httpClient: OkHttpClient by lazy {
    OkHttpClient.Builder()
      .connectTimeout(30, TimeUnit.SECONDS)
      .readTimeout(30, TimeUnit.SECONDS)
      .writeTimeout(30, TimeUnit.SECONDS)
      .build()
  }

  init {
    // The React context is alive as soon as this module is constructed
    isReactContextAlive = true
    currentReactContext = reactApplicationContext
    // Warm the in-memory store with anything persisted while the bridge was dead
    loadPersistedLocations()
    // Wire geofence transitions to JS events
    startGeofenceCallback()
  }

  override fun getName() = NAME

  // The generated Android TurboModule base declares these abstract (RN reserves
  // addListener/removeListeners for NativeEventEmitter). No-op — events are
  // delivered via RCTDeviceEventEmitter.emit().
  override fun addListener(eventName: String) = Unit
  override fun removeListeners(count: Double) = Unit

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private fun hasLocationPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      reactApplicationContext, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED ||
    ContextCompat.checkSelfPermission(
      reactApplicationContext, Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
  }

  /** "FOREGROUND" when the UI is resumed, otherwise "BACKGROUND". */
  private fun currentAppState(): String {
    return if (reactApplicationContext.lifecycleState == LifecycleState.RESUMED)
      "FOREGROUND" else "BACKGROUND"
  }

  private fun sendEvent(eventName: String, params: Any?) {
    try {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(eventName, params)
    } catch (e: Exception) {
      android.util.Log.w(NAME, "sendEvent($eventName) failed: ${e.message}")
    }
  }

  private fun locationToMap(location: Location): WritableMap {
    val coords = Arguments.createMap().apply {
      putDouble("latitude", location.latitude)
      putDouble("longitude", location.longitude)
      putDouble("accuracy", location.accuracy.toDouble())
      putDouble("altitude", location.altitude)
      putDouble("altitudeAccuracy",
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
          location.verticalAccuracyMeters.toDouble() else -1.0)
      putDouble("heading", location.bearing.toDouble())
      putDouble("speed", location.speed.toDouble())
    }
    lastLocation?.let { odometer += it.distanceTo(location).toDouble() }
    lastLocation = location

    // Read the latest detected activity (works in every state — the receiver
    // persists it to prefs even when the app is killed).
    var activityType = BgGeolocationActivityRecognitionReceiver.readActivityType(reactApplicationContext)
    val activityConf = BgGeolocationActivityRecognitionReceiver.readActivityConfidence(reactApplicationContext)
    val detectedMoving = BgGeolocationActivityRecognitionReceiver.readIsMoving(reactApplicationContext)
    val moving = detectedMoving || location.speed > 0.5f
    if (!detectedMoving && moving && activityType == "unknown") {
      activityType = "moving"
    }
    isMoving = moving

    return Arguments.createMap().apply {
      putString("uuid", UUID.randomUUID().toString())
      putString("timestamp",
        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
          java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
          .format(java.util.Date(location.time)))
      putMap("coords", coords)
      putMap("activity", Arguments.createMap().apply {
        putString("type", activityType)
        putInt("confidence", activityConf)
      })
      putMap("battery", Arguments.createMap().apply {
        putDouble("level", getBatteryLevel())
        putBoolean("is_charging", isCharging())
      })
      putBoolean("is_moving", moving)
      putDouble("odometer", odometer)
    }
  }

  private fun getBatteryLevel(): Double {
    return try {
      val bm = reactApplicationContext.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) / 100.0
      } else -1.0
    } catch (e: Exception) { -1.0 }
  }

  private fun isCharging(): Boolean {
    return try {
      val intentFilter = android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED)
      val batteryStatus = reactApplicationContext.registerReceiver(null, intentFilter)
      val status = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
      status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
        status == android.os.BatteryManager.BATTERY_STATUS_FULL
    } catch (e: Exception) { false }
  }

  private fun stateMap(): WritableMap = Arguments.createMap().apply {
    putBoolean("enabled", isTracking)
    putBoolean("schedulerEnabled", false)
    putInt("trackingMode", 1)
    putDouble("odometer", odometer)
    putBoolean("debug", config.optBoolean("debug", false))
    putInt("logLevel", config.optInt("logLevel", 3))
  }

  private fun startForegroundService() {
    val notifConfig = config.optJSONObject("notification")
    val title = notifConfig?.optString("title") ?: "BG Geolocation"
    val text  = notifConfig?.optString("text")  ?: "Tracking location in background"
    BgGeolocationForegroundService.start(reactApplicationContext, title, text)
  }

  private fun stopForegroundService() {
    BgGeolocationForegroundService.stop(reactApplicationContext)
  }

  private fun persistTrackingState(enabled: Boolean) {
    BgGeolocationBootReceiver.setTrackingEnabled(reactApplicationContext, enabled)
  }

  /** Persist runtime config needed by the ForegroundService + MotionStateMachine. */
  private fun persistServiceConfig() {
    // The "tracking period" is how often we force a FRESH fix in all states
    // (including kill). Prefer heartbeatInterval (seconds); fall back to
    // locationUpdateInterval (ms); default 60s.
    val periodMs = when {
      config.has("heartbeatInterval")      -> config.optLong("heartbeatInterval", 60L) * 1000L
      config.has("locationUpdateInterval") -> config.optLong("locationUpdateInterval", 60000L)
      else                                 -> 60000L
    }
    prefs.edit()
      .putLong("trackingPeriodMs", periodMs)
      .putLong("locationUpdateInterval", config.optLong("locationUpdateInterval", periodMs))
      .putFloat("distanceFilter", config.optDouble("distanceFilter", 10.0).toFloat())
      .putLong("stopTimeout", config.optLong("stopTimeout", 60L))
      .putBoolean("autoSync", config.optBoolean("autoSync", true))
      .putString("url",     config.optString("url", ""))
      .putString("method",  config.optString("method", "POST"))
      .putString("headers", config.optJSONObject("headers")?.toString() ?: "{}")
      .putString("params",  config.optJSONObject("params")?.toString()  ?: "{}")
      .apply()
  }

  // ─── Location disk persistence ──────────────────────────────────────────────
  // Mirrors iOS persistLocationToDisk / loadPersistedLocations so getLocations()
  // returns records even after the app is killed and relaunched.

  private fun persistLocationToDisk(map: WritableMap) {
    try {
      val arr = JSONArray(prefs.getString("persistedLocations", "[]"))
      arr.put(JSONObject(map.toHashMap()))
      // Trim to cap
      while (arr.length() > maxPersistedLocations) arr.remove(0)
      prefs.edit().putString("persistedLocations", arr.toString()).apply()
    } catch (e: Exception) {
      android.util.Log.w(NAME, "persistLocationToDisk failed: ${e.message}")
    }
  }

  private fun loadPersistedLocations() {
    try {
      locationStore.clear()
      val arr = JSONArray(prefs.getString("persistedLocations", "[]"))
      for (i in 0 until arr.length()) {
        val obj = arr.getJSONObject(i)
        locationStore.add(jsonToWritableMap(obj))
      }
      if (arr.length() > 0) {
        android.util.Log.d(NAME, "Loaded ${arr.length()} persisted locations from disk")
      }
    } catch (e: Exception) {
      android.util.Log.w(NAME, "loadPersistedLocations failed: ${e.message}")
    }
  }

  private fun clearPersistedLocations() {
    prefs.edit().remove("persistedLocations").apply()
  }

  private fun rewritePersistedLocations() {
    try {
      val arr = JSONArray()
      locationStore.forEach { arr.put(JSONObject(it.toHashMap())) }
      prefs.edit().putString("persistedLocations", arr.toString()).apply()
    } catch (e: Exception) {
      android.util.Log.w(NAME, "rewritePersistedLocations failed: ${e.message}")
    }
  }

  /** Convert a JSONObject (possibly nested) into a WritableMap. */
  private fun jsonToWritableMap(json: JSONObject): WritableMap {
    val map = Arguments.createMap()
    json.keys().forEach { key ->
      when (val value = json.get(key)) {
        is JSONObject -> map.putMap(key, jsonToWritableMap(value))
        is JSONArray  -> map.putArray(key, jsonToWritableArray(value))
        is Boolean    -> map.putBoolean(key, value)
        is Int        -> map.putInt(key, value)
        is Long       -> map.putDouble(key, value.toDouble())
        is Double     -> map.putDouble(key, value)
        is String     -> map.putString(key, value)
        else          -> map.putString(key, value.toString())
      }
    }
    return map
  }

  private fun jsonToWritableArray(json: JSONArray): WritableArray {
    val arr = Arguments.createArray()
    for (i in 0 until json.length()) {
      when (val value = json.get(i)) {
        is JSONObject -> arr.pushMap(jsonToWritableMap(value))
        is JSONArray  -> arr.pushArray(jsonToWritableArray(value))
        is Boolean    -> arr.pushBoolean(value)
        is Int        -> arr.pushInt(value)
        is Long       -> arr.pushDouble(value.toDouble())
        is Double     -> arr.pushDouble(value)
        is String     -> arr.pushString(value)
        else          -> arr.pushString(value.toString())
      }
    }
    return arr
  }

  // ─── Heartbeat ────────────────────────────────────────────────────────────
  // Mirrors iOS heartbeat timer — emits a `heartbeat` event on a fixed interval.

  private fun startHeartbeat() {
    val intervalSec = config.optLong("heartbeatInterval", 0L)
    if (intervalSec <= 0L) return
    stopHeartbeat()
    heartbeatHandler = Handler(Looper.getMainLooper())
    heartbeatRunnable = object : Runnable {
      override fun run() {
        val event = Arguments.createMap().apply {
          putInt("shakes", 0)
          lastLocation?.let { putMap("location", locationToMap(it)) }
        }
        sendEvent("heartbeat", event)
        heartbeatHandler?.postDelayed(this, intervalSec * 1000L)
      }
    }
    heartbeatHandler?.postDelayed(heartbeatRunnable!!, intervalSec * 1000L)
  }

  private fun stopHeartbeat() {
    heartbeatRunnable?.let { heartbeatHandler?.removeCallbacks(it) }
    heartbeatRunnable = null
    heartbeatHandler = null
  }

  // ─── Geofencing (GeofencingClient) ──────────────────────────────────────────
  // Mirrors iOS CLCircularRegion monitoring — fires ENTER / EXIT / DWELL even in
  // background & kill state via an OS-owned PendingIntent.

  private fun getGeofencePendingIntent(): android.app.PendingIntent {
    geofencePendingIntent?.let { return it }
    val intent = android.content.Intent(
      reactApplicationContext, BgGeolocationGeofenceReceiver::class.java
    )
    val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
      android.app.PendingIntent.FLAG_MUTABLE
    val pi = android.app.PendingIntent.getBroadcast(reactApplicationContext, 3001, intent, flags)
    geofencePendingIntent = pi
    return pi
  }

  @SuppressLint("MissingPermission")
  private fun registerGeofence(gf: ReadableMap) {
    val identifier = gf.getString("identifier") ?: return
    if (!gf.hasKey("latitude") || !gf.hasKey("longitude") || !gf.hasKey("radius")) return

    if (geofencingClient == null) {
      geofencingClient = LocationServices.getGeofencingClient(reactApplicationContext)
    }

    var transitions = 0
    val notifyEntry = !gf.hasKey("notifyOnEntry") || gf.getBoolean("notifyOnEntry")
    val notifyExit  = !gf.hasKey("notifyOnExit")  || gf.getBoolean("notifyOnExit")
    val notifyDwell = gf.hasKey("notifyOnDwell") && gf.getBoolean("notifyOnDwell")
    if (notifyEntry) transitions = transitions or Geofence.GEOFENCE_TRANSITION_ENTER
    if (notifyExit)  transitions = transitions or Geofence.GEOFENCE_TRANSITION_EXIT
    if (notifyDwell) transitions = transitions or Geofence.GEOFENCE_TRANSITION_DWELL

    val builder = Geofence.Builder()
      .setRequestId(identifier)
      .setCircularRegion(gf.getDouble("latitude"), gf.getDouble("longitude"), gf.getDouble("radius").toFloat())
      .setExpirationDuration(Geofence.NEVER_EXPIRE)
      .setTransitionTypes(transitions)
    if (notifyDwell) {
      builder.setLoiteringDelay(if (gf.hasKey("loiteringDelay")) gf.getInt("loiteringDelay") else 30000)
    }

    val request = GeofencingRequest.Builder()
      .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
      .addGeofence(builder.build())
      .build()

    geofencingClient?.addGeofences(request, getGeofencePendingIntent())
      ?.addOnFailureListener { e ->
        android.util.Log.w(NAME, "addGeofence '$identifier' failed: ${e.message}")
      }
  }

  /** Wire up the receiver so geofence transitions emit a `geofence` event to JS. */
  private fun startGeofenceCallback() {
    BgGeolocationGeofenceReceiver.setCallback { identifier, action ->
      val event = Arguments.createMap().apply {
        putString("identifier", identifier)
        putString("action", action)
        lastLocation?.let { putMap("location", locationToMap(it)) }
      }
      // Bridge is alive in this callback — emit straight to JS.
      // (Kill-state geofence delivery is handled by the OS-owned geofence
      //  PendingIntent + receiver, which can route through the headless task.)
      sendEvent("geofence", event)
    }
  }

  // ─── HTTP Sync ────────────────────────────────────────────────────────────

  /**
   * POST a single location (or batch) to the configured URL using OkHttp.
   * Reads `url`, `method`, `headers`, and `params` from config.
   */
  private fun syncLocation(locationMap: WritableMap) {
    val url = config.optString("url", "")
    if (url.isEmpty()) return

    scope.launch {
      try {
        val method = config.optString("method", "POST").uppercase()
        val extraHeaders = config.optJSONObject("headers")
        val extraParams = config.optJSONObject("params")

        // Build JSON body: wrap location in configured params if any
        val body = JSONObject().apply {
          put("location", JSONObject().apply {
            put("uuid", locationMap.getString("uuid") ?: "")
            put("timestamp", locationMap.getString("timestamp") ?: "")
            val coords = locationMap.getMap("coords")
            if (coords != null) {
              put("coords", JSONObject().apply {
                put("latitude", coords.getDouble("latitude"))
                put("longitude", coords.getDouble("longitude"))
                put("accuracy", coords.getDouble("accuracy"))
                put("altitude", coords.getDouble("altitude"))
                put("heading", coords.getDouble("heading"))
                put("speed", coords.getDouble("speed"))
              })
            }
            put("is_moving", locationMap.getBoolean("is_moving"))
            put("odometer", locationMap.getDouble("odometer"))
          })
          extraParams?.keys()?.forEach { key -> put(key, extraParams[key]) }
        }

        val mediaType = "application/json; charset=utf-8".toMediaType()
        val requestBody = body.toString().toRequestBody(mediaType)

        val requestBuilder = Request.Builder().url(url)
        extraHeaders?.keys()?.forEach { key ->
          requestBuilder.addHeader(key, extraHeaders.optString(key))
        }

        when (method) {
          "PUT"   -> requestBuilder.put(requestBody)
          "PATCH" -> requestBuilder.patch(requestBody)
          else    -> requestBuilder.post(requestBody)
        }

        httpClient.newCall(requestBuilder.build()).execute().use { response ->
          if (config.optBoolean("debug", false)) {
            android.util.Log.d(NAME, "HTTP sync: ${response.code} ${response.message}")
          }
        }
      } catch (e: IOException) {
        android.util.Log.w(NAME, "HTTP sync failed: ${e.message}")
      }
    }
  }

  /**
   * Batch sync all stored locations to the server.
   */
  private fun syncBatch(locations: List<WritableMap>, onSuccess: () -> Unit, onFailure: (String) -> Unit) {
    val url = config.optString("url", "")
    if (url.isEmpty()) { onFailure("NO_URL_CONFIGURED"); return }

    scope.launch {
      try {
        val method = config.optString("method", "POST").uppercase()
        val extraHeaders = config.optJSONObject("headers")
        val extraParams = config.optJSONObject("params")

        val locationsArray = JSONArray()
        locations.forEach { locationMap ->
          val obj = JSONObject().apply {
            put("uuid", locationMap.getString("uuid") ?: "")
            put("timestamp", locationMap.getString("timestamp") ?: "")
            val coords = locationMap.getMap("coords")
            if (coords != null) {
              put("coords", JSONObject().apply {
                put("latitude", coords.getDouble("latitude"))
                put("longitude", coords.getDouble("longitude"))
                put("accuracy", coords.getDouble("accuracy"))
                put("altitude", coords.getDouble("altitude"))
                put("heading", coords.getDouble("heading"))
                put("speed", coords.getDouble("speed"))
              })
            }
            put("is_moving", locationMap.getBoolean("is_moving"))
            put("odometer", locationMap.getDouble("odometer"))
          }
          locationsArray.put(obj)
        }

        val body = JSONObject().apply {
          put("locations", locationsArray)
          extraParams?.keys()?.forEach { key -> put(key, extraParams[key]) }
        }

        val mediaType = "application/json; charset=utf-8".toMediaType()
        val requestBody = body.toString().toRequestBody(mediaType)

        val requestBuilder = Request.Builder().url(url)
        extraHeaders?.keys()?.forEach { key ->
          requestBuilder.addHeader(key, extraHeaders.optString(key))
        }
        when (method) {
          "PUT"   -> requestBuilder.put(requestBody)
          "PATCH" -> requestBuilder.patch(requestBody)
          else    -> requestBuilder.post(requestBody)
        }

        httpClient.newCall(requestBuilder.build()).execute().use { response ->
          if (response.isSuccessful) {
            onSuccess()
          } else {
            onFailure("HTTP ${response.code}: ${response.message}")
          }
        }
      } catch (e: IOException) {
        onFailure(e.message ?: "IO error")
      }
    }
  }

  // ─── Activity Recognition ─────────────────────────────────────────────────

  @SuppressLint("MissingPermission")
  private fun startActivityRecognition() {
    if (ContextCompat.checkSelfPermission(
        reactApplicationContext, Manifest.permission.ACTIVITY_RECOGNITION
      ) != PackageManager.PERMISSION_GRANTED) return

    activityRecognitionClient = ActivityRecognition.getClient(reactApplicationContext)
    val intent = android.content.Intent(
      reactApplicationContext,
      BgGeolocationActivityRecognitionReceiver::class.java
    )
    activityPendingIntent = android.app.PendingIntent.getBroadcast(
      reactApplicationContext,
      2001,
      intent,
      android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_MUTABLE
    )
    // The OS owns this PendingIntent, so updates keep arriving at the receiver
    // even after the app is killed. The receiver persists + emits motionchange itself.
    activityRecognitionClient.requestActivityUpdates(
      config.optLong("activityRecognitionInterval", 10000L),
      activityPendingIntent!!
    )
    android.util.Log.d(TEST_TAG, "Activity recognition requested")
  }

  private fun stopActivityRecognition() {
    try {
      activityPendingIntent?.let {
        activityRecognitionClient.removeActivityUpdates(it)
        it.cancel()
        activityPendingIntent = null
      }
    } catch (e: Exception) {
      android.util.Log.w(NAME, "stopActivityRecognition: ${e.message}")
    }
  }

  // ─── Core ─────────────────────────────────────────────────────────────────

  override fun ready(config: ReadableMap, success: Callback, failure: Callback) {
    try {
      this.config = JSONObject(config.toHashMap())
      persistServiceConfig()
      if (config.hasKey("startOnBoot") && config.getBoolean("startOnBoot")) {
        val wasTracking = BgGeolocationBootReceiver.isTrackingEnabled(reactApplicationContext)
        if (wasTracking && !isTracking) {
          val noop = Callback { }
          start(noop, noop)
        }
      }
      success.invoke(stateMap())
    } catch (e: Exception) {
      failure.invoke(e.message)
    }
  }

  override fun configure(config: ReadableMap, success: Callback, failure: Callback) {
    ready(config, success, failure)
  }

  override fun reset(config: ReadableMap, success: Callback, failure: Callback) {
    this.config = JSONObject()
    persistTrackingState(false)
    ready(config, success, failure)
  }

  override fun setConfig(config: ReadableMap, success: Callback, failure: Callback) {
    try {
      val newConfig = JSONObject(config.toHashMap())
      newConfig.keys().forEach { key -> this.config.put(key, newConfig[key]) }
      persistServiceConfig()
      success.invoke(stateMap())
    } catch (e: Exception) {
      failure.invoke(e.message)
    }
  }

  override fun getState(success: Callback, failure: Callback) {
    success.invoke(stateMap())
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @SuppressLint("MissingPermission")
  override fun start(success: Callback, failure: Callback) {
    try {
      if (!hasLocationPermission()) {
        failure.invoke("PERMISSION_DENIED")
        return
      }

      isTracking = true
      persistTrackingState(true)
      persistServiceConfig()
      // The ForegroundService is the SINGLE active location source. It requests
      // FusedLocation updates itself (with foregroundServiceType=location), which
      // is what gives continuous fresh GPS + the OS location indicator in the
      // background and after kill. The module no longer registers its own updates.
      startForegroundService()
      android.util.Log.d(TEST_TAG, "▶️ START tracking — ForegroundService owns location (state=${currentAppState()})")

      // Activity recognition for motionchange events
      startActivityRecognition()

      // Heartbeat timer (if configured)
      startHeartbeat()

      // Re-register any geofences added before start / surviving a relaunch
      geofenceStore.forEach { registerGeofence(it) }

      success.invoke(stateMap())
    } catch (e: Exception) {
      isTracking = false
      persistTrackingState(false)
      stopForegroundService()
      stopActivityRecognition()
      stopHeartbeat()
      android.util.Log.e(TEST_TAG, "START failed: ${e.message}", e)
      failure.invoke(e.message ?: "START_FAILED")
    }
  }

  override fun stop(success: Callback, failure: Callback) {
    isTracking = false
    persistTrackingState(false)
    // The ForegroundService owns location updates — stopping it stops tracking.
    stopForegroundService()
    stopActivityRecognition()
    stopHeartbeat()
    // Clear the motion state machine so it re-initializes on next start
    prefs.edit().remove("motion_initialized").remove("motion_still_since").apply()
    android.util.Log.d(TEST_TAG, "⏹️ STOP tracking")
    success.invoke(stateMap())
  }

  override fun startSchedule(success: Callback, failure: Callback) {
    success.invoke(stateMap())
  }

  override fun stopSchedule(success: Callback, failure: Callback) {
    success.invoke(stateMap())
  }

  override fun startGeofences(success: Callback, failure: Callback) {
    geofenceStore.forEach { registerGeofence(it) }
    success.invoke(stateMap())
  }

  // ─── Background Task ──────────────────────────────────────────────────────

  override fun beginBackgroundTask(success: Callback, failure: Callback) {
    success.invoke(1)
  }

  override fun finish(taskId: Double, success: Callback, failure: Callback) {
    success.invoke(taskId)
  }

  // ─── Motion / Location ────────────────────────────────────────────────────

  override fun changePace(isMoving: Boolean, success: Callback, failure: Callback) {
    this.isMoving = isMoving
    val event = Arguments.createMap().apply {
      putBoolean("isMoving", isMoving)
      lastLocation?.let { putMap("location", locationToMap(it)) }
    }
    sendEvent("motionchange", event)
    success.invoke()
  }

  @SuppressLint("MissingPermission")
  override fun getCurrentPosition(options: ReadableMap, success: Callback, failure: Callback) {
    if (!hasLocationPermission()) { failure.invoke("PERMISSION_DENIED"); return }
    if (!::fusedClient.isInitialized) {
      fusedClient = LocationServices.getFusedLocationProviderClient(reactApplicationContext)
    }
    fusedClient.lastLocation.addOnSuccessListener { location ->
      if (location != null) {
        success.invoke(locationToMap(location))
      } else {
        // Request a fresh single update
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 0)
          .setMaxUpdates(1)
          .build()
        val cb = object : LocationCallback() {
          override fun onLocationResult(result: LocationResult) {
            fusedClient.removeLocationUpdates(this)
            result.lastLocation?.let { success.invoke(locationToMap(it)) }
              ?: failure.invoke("LOCATION_UNAVAILABLE")
          }
        }
        fusedClient.requestLocationUpdates(request, cb, Looper.getMainLooper())
      }
    }.addOnFailureListener {
      failure.invoke(it.message ?: "LOCATION_UNAVAILABLE")
    }
  }

  @SuppressLint("MissingPermission")
  override fun watchPosition(options: ReadableMap, success: Callback, failure: Callback) {
    if (!hasLocationPermission()) { failure.invoke("PERMISSION_DENIED"); return }
    if (!::fusedClient.isInitialized) {
      fusedClient = LocationServices.getFusedLocationProviderClient(reactApplicationContext)
    }
    val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
      .setMinUpdateDistanceMeters(0f)
      .build()
    watchPositionCallback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        result.lastLocation?.let { sendEvent("watchposition", locationToMap(it)) }
      }
    }
    fusedClient.requestLocationUpdates(request, watchPositionCallback!!, Looper.getMainLooper())
    success.invoke()
  }

  override fun stopWatchPosition(success: Callback, failure: Callback) {
    watchPositionCallback?.let {
      if (::fusedClient.isInitialized) fusedClient.removeLocationUpdates(it)
    }
    watchPositionCallback = null
    success.invoke()
  }

  // ─── Permissions ──────────────────────────────────────────────────────────

  override fun requestPermission(success: Callback, failure: Callback) {
    if (hasLocationPermission()) success.invoke(3) else failure.invoke(2)
  }

  override fun requestTemporaryFullAccuracy(purpose: String, success: Callback, failure: Callback) {
    success.invoke(0)
  }

  override fun getProviderState(success: Callback, failure: Callback) {
    val lm = reactApplicationContext.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
    val gpsEnabled = lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
    val netEnabled = lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
    success.invoke(Arguments.createMap().apply {
      putBoolean("enabled", gpsEnabled || netEnabled)
      putBoolean("gps", gpsEnabled)
      putBoolean("network", netEnabled)
      putInt("status", if (hasLocationPermission()) 3 else 2)
      putInt("accuracyAuthorization", 0)
    })
  }

  // ─── HTTP & Persistence ───────────────────────────────────────────────────

  override fun getLocations(success: Callback, failure: Callback) {
    loadPersistedLocations()
    success.invoke(Arguments.createArray().also { arr -> locationStore.forEach { arr.pushMap(it) } })
  }

  override fun getCount(success: Callback, failure: Callback) {
    loadPersistedLocations()
    success.invoke(locationStore.size)
  }

  override fun destroyLocations(success: Callback, failure: Callback) {
    locationStore.clear()
    clearPersistedLocations()
    success.invoke()
  }

  override fun destroyLocation(uuid: String, success: Callback, failure: Callback) {
    locationStore.removeAll { it.getString("uuid") == uuid }
    rewritePersistedLocations()
    success.invoke()
  }

  override fun insertLocation(location: ReadableMap, success: Callback, failure: Callback) {
    val map = Arguments.createMap().apply { merge(location) }
    locationStore.add(map)
    persistLocationToDisk(map)
    success.invoke(map)
  }

  override fun sync(success: Callback, failure: Callback) {
    loadPersistedLocations()
    if (config.optString("url", "").isEmpty()) { failure.invoke("NO_URL_CONFIGURED"); return }
    val snapshot = locationStore.toList()
    locationStore.clear()
    clearPersistedLocations()
    syncBatch(snapshot,
      onSuccess = {
        val arr = Arguments.createArray().also { a -> snapshot.forEach { a.pushMap(it) } }
        success.invoke(arr)
      },
      onFailure = { msg ->
        // restore on failure
        locationStore.addAll(0, snapshot)
        rewritePersistedLocations()
        failure.invoke(msg)
      }
    )
  }

  // ─── Odometer ─────────────────────────────────────────────────────────────

  override fun getOdometer(success: Callback, failure: Callback) { success.invoke(odometer) }

  override fun setOdometer(value: Double, success: Callback, failure: Callback) {
    odometer = value; success.invoke(Arguments.createMap())
  }

  // ─── Geofences ────────────────────────────────────────────────────────────

  override fun addGeofence(config: ReadableMap, success: Callback, failure: Callback) {
    val map = Arguments.createMap().apply { merge(config) }
    geofenceStore.removeAll { it.getString("identifier") == config.getString("identifier") }
    geofenceStore.add(map)
    // Actually monitor it via GeofencingClient (works in bg/kill state)
    registerGeofence(config)
    success.invoke()
  }

  override fun addGeofences(geofences: ReadableArray, success: Callback, failure: Callback) {
    for (i in 0 until geofences.size()) {
      val gf = geofences.getMap(i) ?: continue
      val id = gf.getString("identifier")
      geofenceStore.removeAll { it.getString("identifier") == id }
      geofenceStore.add(Arguments.createMap().apply { merge(gf) })
      registerGeofence(gf)
    }
    success.invoke()
  }

  override fun removeGeofence(identifier: String, success: Callback, failure: Callback) {
    geofenceStore.removeAll { it.getString("identifier") == identifier }
    geofencingClient?.removeGeofences(listOf(identifier))
    success.invoke()
  }

  override fun removeGeofences(success: Callback, failure: Callback) {
    geofenceStore.clear()
    geofencePendingIntent?.let { geofencingClient?.removeGeofences(it) }
    success.invoke()
  }

  override fun getGeofences(success: Callback, failure: Callback) {
    success.invoke(Arguments.createArray().also { a -> geofenceStore.forEach { a.pushMap(it) } })
  }

  override fun getGeofence(identifier: String, success: Callback, failure: Callback) {
    val found = geofenceStore.find { it.getString("identifier") == identifier }
    if (found != null) success.invoke(found) else failure.invoke("NOT_FOUND: $identifier")
  }

  override fun geofenceExists(identifier: String, callback: Callback) {
    callback.invoke(geofenceStore.any { it.getString("identifier") == identifier })
  }

  // ─── Logging ──────────────────────────────────────────────────────────────

  override fun log(level: String, message: String) {
    when (level) {
      "error" -> android.util.Log.e(NAME, message)
      "warn"  -> android.util.Log.w(NAME, message)
      "debug" -> android.util.Log.d(NAME, message)
      else    -> android.util.Log.i(NAME, message)
    }
  }

  override fun setLogLevel(value: Double, success: Callback, failure: Callback) {
    config.put("logLevel", value.toInt()); success.invoke(stateMap())
  }

  override fun getLog(success: Callback, failure: Callback) { success.invoke("") }
  override fun destroyLog(success: Callback, failure: Callback) { success.invoke() }
  override fun emailLog(email: String, success: Callback, failure: Callback) { success.invoke() }

  // ─── Utility ──────────────────────────────────────────────────────────────

  override fun isPowerSaveMode(success: Callback, failure: Callback) {
    val pm = reactApplicationContext.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
    success.invoke(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) pm.isPowerSaveMode else false)
  }

  override fun getSensors(success: Callback, failure: Callback) {
    val sm = reactApplicationContext.getSystemService(Context.SENSOR_SERVICE) as android.hardware.SensorManager
    val has = { type: Int -> sm.getDefaultSensor(type) != null }
    success.invoke(Arguments.createMap().apply {
      putString("platform", "android")
      putBoolean("accelerometer", has(android.hardware.Sensor.TYPE_ACCELEROMETER))
      putBoolean("gyroscope",     has(android.hardware.Sensor.TYPE_GYROSCOPE))
      putBoolean("magnetometer",  has(android.hardware.Sensor.TYPE_MAGNETIC_FIELD))
      putBoolean("motionHardware",has(android.hardware.Sensor.TYPE_STEP_DETECTOR))
    })
  }

  override fun getDeviceInfo(success: Callback, failure: Callback) {
    success.invoke(Arguments.createMap().apply {
      putString("uuid", android.provider.Settings.Secure.getString(
        reactApplicationContext.contentResolver, android.provider.Settings.Secure.ANDROID_ID)
        ?: UUID.randomUUID().toString())
      putString("model", Build.MODEL)
      putString("platform", "android")
      putString("manufacturer", Build.MANUFACTURER)
      putString("version", Build.VERSION.RELEASE)
      putString("framework", "react-native")
      putString("frameworkVersion", "unknown")
    })
  }

  override fun playSound(soundId: Double) {
    try {
      val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
      android.media.RingtoneManager.getRingtone(reactApplicationContext, uri)?.play()
    } catch (e: Exception) { android.util.Log.w(NAME, "playSound failed: ${e.message}") }
  }


  override fun invalidate() {
    isReactContextAlive = false
    if (currentReactContext === reactApplicationContext) {
      currentReactContext = null
    }
    scope.cancel()
    if (::fusedClient.isInitialized) {
      watchPositionCallback?.let { fusedClient.removeLocationUpdates(it) }
    }
    stopActivityRecognition()
    stopHeartbeat()
    // Do NOT stop the foreground service — it owns location updates and must keep
    // running after the JS bridge tears down (this is what enables kill-state tracking).
    super.invalidate()
  }
}
