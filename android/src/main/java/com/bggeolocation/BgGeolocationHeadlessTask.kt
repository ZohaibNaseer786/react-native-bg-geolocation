package com.bggeolocation

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * BgGeolocationHeadlessTask
 *
 * Allows JavaScript to run in a headless context when the app is killed but
 * the ForegroundService is still alive and delivering location updates.
 *
 * On the JS side the app must register:
 *   AppRegistry.registerHeadlessTask('BackgroundGeolocation', () => require('./headlessTask'));
 *
 * The headless task function receives { name: 'location', params: <locationObject> }.
 *
 * Flow:
 *   1. BgGeolocationModule (or ForegroundService) calls BgGeolocationHeadlessTask.onLocation()
 *      when a new location arrives.
 *   2. onLocation() enqueues the event bundle and starts this service via an Intent.
 *   3. Android calls onStartCommand → getTaskConfig → HeadlessJsTaskService manages the JS runtime.
 *   4. JS task runs, finishes, and the runtime is cleaned up automatically.
 */
class BgGeolocationHeadlessTask : HeadlessJsTaskService() {

  companion object {
    private const val TAG = "BgGeoHeadlessTask"
    private const val TASK_NAME = "BackgroundGeolocation"
    private const val TASK_TIMEOUT_MS = 30_000L

    /** Thread-safe queue of pending location events to be dispatched as headless tasks. */
    private val pendingEvents = ConcurrentLinkedQueue<Bundle>()

    /**
     * Called from BgGeolocationModule / ForegroundService whenever a location update arrives.
     * If the React context is alive the normal event emitter path is used in parallel;
     * this path ensures JS executes even when the React bridge is not yet available
     * (i.e. the app is in the killed/terminated state).
     */
    fun onLocation(context: Context, locationMap: WritableMap) {
      onEvent(context, "location", locationMap)
    }

    /**
     * Generic dispatcher for any event type (location, geofence, motionchange, …).
     * Enqueues { name, params } and starts the service so getTaskConfig fires.
     */
    fun onEvent(context: Context, eventName: String, params: WritableMap) {
      try {
        val bundle = writableMapToBundle(params)
        val taskBundle = Bundle().apply {
          putString("name", eventName)
          putBundle("params", bundle)
        }
        pendingEvents.offer(taskBundle)

        val intent = Intent(context, BgGeolocationHeadlessTask::class.java)
        context.startService(intent)
        HeadlessJsTaskService.acquireWakeLockNow(context)
        Log.d(TAG, "onEvent($eventName): queued headless task (queue size=${pendingEvents.size})")
      } catch (e: Exception) {
        Log.w(TAG, "onEvent($eventName): failed to queue headless task: ${e.message}")
      }
    }

    // ─── Serialisation helpers ─────────────────────────────────────────────

    private fun writableMapToBundle(map: WritableMap): Bundle {
      val bundle = Bundle()
      // Iterate using the underlying HashMap representation
      val hashMap = map.toHashMap()
      for ((key, value) in hashMap) {
        when (value) {
          is Boolean -> bundle.putBoolean(key, value)
          is Int     -> bundle.putInt(key, value)
          is Long    -> bundle.putLong(key, value)
          is Double  -> bundle.putDouble(key, value)
          is Float   -> bundle.putFloat(key, value)
          is String  -> bundle.putString(key, value)
          is Map<*, *> -> {
            @Suppress("UNCHECKED_CAST")
            val nestedMap = Arguments.makeNativeMap(value as Map<String, Any>)
            bundle.putBundle(key, writableMapToBundle(nestedMap))
          }
          else -> bundle.putString(key, value?.toString())
        }
      }
      return bundle
    }
  }

  // ─── HeadlessJsTaskService ────────────────────────────────────────────────

  /**
   * Called by the Android framework after startService(). Dequeue the next
   * pending event and return a task config for the React headless JS runtime.
   * If the queue is empty there is nothing to run — return null to stop the service.
   */
  override fun getTaskConfig(intent: Intent?): HeadlessJsTaskConfig? {
    val eventBundle = pendingEvents.poll()
    if (eventBundle == null) {
      Log.d(TAG, "getTaskConfig: no pending events — stopping service")
      return null
    }

    val taskData = Arguments.fromBundle(eventBundle)
    Log.d(TAG, "getTaskConfig: dispatching headless task '${eventBundle.getString("name")}'")

    return HeadlessJsTaskConfig(
      TASK_NAME,
      taskData,
      TASK_TIMEOUT_MS,
      true // allowedInForeground — safe to run even if app is in the foreground
    )
  }

  override fun onHeadlessJsTaskStart(taskId: Int) {
    super.onHeadlessJsTaskStart(taskId)
    Log.d(TAG, "Headless JS task started (id=$taskId)")
  }

  override fun onHeadlessJsTaskFinish(taskId: Int) {
    super.onHeadlessJsTaskFinish(taskId)
    Log.d(TAG, "Headless JS task finished (id=$taskId)")
    // If more events are waiting, re-start so getTaskConfig is called again
    if (pendingEvents.isNotEmpty()) {
      val intent = Intent(this, BgGeolocationHeadlessTask::class.java)
      startService(intent)
    }
  }
}
