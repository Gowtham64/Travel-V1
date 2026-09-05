package com.example.travel_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.travel_app.car.CarNavState
import com.example.travel_app.car.LatLngD
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import java.util.Locale
import com.example.travel_app.car.FuelStop
import com.example.travel_app.car.WaypointInfo

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    private val tripNotifId = 4201
    private val reminderBaseNotifId = 5200
    private val tripChannelId = "trip_progress"
    private val reminderChannelId = "trip_reminders"

    private var notificationChannel: MethodChannel? = null
    private var pendingNotificationPayload: Map<String, Any?>? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent)
        try {
            tts = TextToSpeech(this, this)
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val tripId = intent.getStringExtra("tripId")
        if (!tripId.isNullOrEmpty()) {
            val action = intent.getStringExtra("action") ?: "trip_start"
            val destination = intent.getStringExtra("destination") ?: ""
            val departureTime = intent.getStringExtra("departureTime") ?: ""
            val payload = mapOf(
                "tripId" to tripId,
                "action" to action,
                "destination" to destination,
                "departureTime" to departureTime
            )
            if (notificationChannel != null) {
                runOnUiThread {
                    notificationChannel?.invokeMethod("onNotificationTapped", payload)
                }
            } else {
                pendingNotificationPayload = payload
            }
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.let {
                it.language = Locale.getDefault()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                    it.setAudioAttributes(attrs)
                }
                ttsReady = true
            }
        }
    }

    private fun speakNavGuidance(text: String) {
        if (!ttsReady || text.isBlank()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "voyplan_nav_${System.currentTimeMillis()}")
            } else {
                @Suppress("DEPRECATION")
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val carChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.travelapp.car")

        // Hook the car display's "End Trip / Stop Navigation" action back to Flutter
        CarNavState.onStopNavigationRequested = {
            runOnUiThread {
                carChannel.invokeMethod("stopNavigationFromCar", null)
            }
        }

        // Live trip-progress & Pre-trip departure reminders, driven from Dart.
        val notifChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.travelapp.notification")
        notificationChannel = notifChan
        pendingNotificationPayload?.let { payload ->
            runOnUiThread {
                notifChan.invokeMethod("onNotificationTapped", payload)
            }
            pendingNotificationPayload = null
        }

        notifChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    ensureTripChannel()
                    ensureReminderChannel()
                    requestNotifPermissionIfNeeded()
                    result.success(null)
                }
                "start" -> {
                    ensureTripChannel()
                    requestNotifPermissionIfNeeded()
                    showTripNotification(call, arriving = false, progress = 0)
                    result.success(null)
                }
                "update" -> {
                    val arriving = call.argument<Boolean>("arriving") ?: false
                    val pct = (((call.argument<Double>("progress")) ?: 0.0) * 100).toInt()
                    showTripNotification(call, arriving, pct.coerceIn(0, 100))
                    result.success(null)
                }
                "end" -> {
                    NotificationManagerCompat.from(this).cancel(tripNotifId)
                    result.success(null)
                }
                "scheduleReminder" -> {
                    ensureReminderChannel()
                    requestNotifPermissionIfNeeded()
                    scheduleDepartureReminder(call)
                    result.success(null)
                }
                "cancelReminder" -> {
                    val idStr = call.argument<String>("id") ?: ""
                    cancelReminder(idStr)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Receives route + maneuver + telemetry from CarPlatformChannel (Dart) and
        // feeds the Android Auto navigation screen via the shared CarNavState.
        carChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setRoute" -> {
                    CarNavState.start = parsePoint(call.argument("start"))
                    CarNavState.end = parsePoint(call.argument("end"))
                    val endMap = call.argument<Map<String, Any?>>("end")
                    CarNavState.destinationName = endMap?.get("name")?.toString() ?: "Destination"
                    CarNavState.waypoints = parseList(call.argument("waypoints"))
                    CarNavState.waypointsInfo = parseWaypointsInfo(call.argument("waypoints"))
                    CarNavState.fuelStops = parseFuelStops(call.argument("fuelStops"))
                    CarNavState.route = parseList(call.argument("coordinates"))
                    CarNavState.notifyChanged()
                    result.success(null)
                }
                "updateNavigation" -> {
                    CarNavState.instruction = call.argument<String>("instruction") ?: ""
                    CarNavState.roadName = call.argument<String>("roadName") ?: ""
                    CarNavState.maneuverType = call.argument<String>("maneuverType") ?: "straight"
                    CarNavState.distanceMeters = num(call.argument("distanceMeters"))
                    CarNavState.formattedDistance = call.argument<String>("formattedDistance") ?: ""
                    CarNavState.speedKmh = num(call.argument("speedKmh"))
                    CarNavState.remainingDistanceKm = num(call.argument("remainingDistanceKm"))
                    CarNavState.remainingDurationMin = num(call.argument("remainingDurationMin")).toInt()
                    CarNavState.formattedEta = call.argument<String>("formattedEta") ?: ""
                    // Live position + heading (updated on every GPS tick).
                    CarNavState.curLat = (call.argument("currentLat") as? Number)?.toDouble() ?: CarNavState.curLat
                    CarNavState.curLng = (call.argument("currentLng") as? Number)?.toDouble() ?: CarNavState.curLng
                    CarNavState.bearing = (call.argument("bearingDeg") as? Number)?.toDouble() ?: CarNavState.bearing
                    val nextFsMap = call.argument<Map<String, Any?>>("nextFuelStop")
                    CarNavState.nextFuelStop = if (nextFsMap != null) parseFuelStop(nextFsMap) else null
                    CarNavState.isNavigating = true
                    CarNavState.notifyChanged()
                    result.success(null)
                }
                "setNavigationState" -> {
                    val nav = call.argument<Boolean>("isNavigating") ?: false
                    CarNavState.isNavigating = nav
                    if (!nav) {
                        // Trip ended: drop the live fix so the idle map isn't stale.
                        CarNavState.curLat = null
                        CarNavState.curLng = null
                        CarNavState.bearing = null
                        CarNavState.nextFuelStop = null
                    }
                    CarNavState.notifyChanged()
                    result.success(null)
                }
                "speakNavigation" -> {
                    val text = call.argument<String>("text") ?: ""
                    speakNavGuidance(text)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun num(v: Any?): Double = (v as? Number)?.toDouble() ?: 0.0

    private fun parsePoint(m: Map<String, Any?>?): LatLngD? {
        if (m == null) return null
        val lat = (m["lat"] as? Number)?.toDouble() ?: return null
        val lng = (m["lng"] as? Number)?.toDouble() ?: return null
        return LatLngD(lat, lng)
    }

    private fun parseList(list: List<Map<String, Any?>>?): List<LatLngD> {
        if (list == null) return emptyList()
        return list.mapNotNull { parsePoint(it) }
    }

    private fun parseWaypointsInfo(list: List<Map<String, Any?>>?): List<WaypointInfo> {
        if (list == null) return emptyList()
        return list.mapNotNull {
            val lat = (it["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
            val lng = (it["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
            val name = it["name"]?.toString() ?: "Waypoint"
            val isFuel = (it["isFuelStop"] as? Boolean) ?: false
            WaypointInfo(name, lat, lng, isFuel)
        }
    }

    private fun parseFuelStop(m: Map<String, Any?>): FuelStop? {
        val lat = (m["lat"] as? Number)?.toDouble() ?: (m["latitude"] as? Number)?.toDouble() ?: return null
        val lng = (m["lng"] as? Number)?.toDouble() ?: (m["longitude"] as? Number)?.toDouble() ?: return null
        val name = m["name"]?.toString() ?: "Fuel Station"
        val fuelType = m["fuelType"]?.toString() ?: "petrol"
        val refillLiters = (m["refillLiters"] as? Number)?.toDouble()
        val estimatedCost = (m["estimatedCost"] as? Number)?.toDouble()
        val distStart = (m["distanceFromStartKm"] as? Number)?.toDouble()
        return FuelStop(name, lat, lng, fuelType, refillLiters, estimatedCost, distStart)
    }

    private fun parseFuelStops(list: List<Map<String, Any?>>?): List<FuelStop> {
        if (list == null) return emptyList()
        return list.mapNotNull { parseFuelStop(it) }
    }

    // ---- Live trip-progress notification -----------------------------------

    private fun ensureTripChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(tripChannelId) == null) {
                val channel = NotificationChannel(
                    tripChannelId, "Trip progress", NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Live progress of your active trip"
                    setShowBadge(false)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun requestNotifPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9021
                )
            }
        }
    }

    private fun showTripNotification(call: MethodCall, arriving: Boolean, progress: Int) {
        val destination = call.argument<String>("destination") ?: "Trip"
        val eta = call.argument<String>("eta") ?: ""
        val distanceLeftKm = call.argument<Double>("distanceLeftKm") ?: 0.0
        val speedKmh = (call.argument<Double>("speedKmh") ?: 0.0).toInt()

        val title = if (arriving) "Arriving now" else if (eta.isEmpty()) "Trip in progress" else "Arriving in $eta"
        val text = if (arriving) {
            "You have reached $destination"
        } else {
            "%.1f km left · %d%% · %d km/h".format(distanceLeftKm, progress, speedKmh)
        }

        val builder = NotificationCompat.Builder(this, tripChannelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(destination)
            .setOnlyAlertOnce(true)
            .setOngoing(!arriving)
            .setAutoCancel(arriving)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (!arriving) builder.setProgress(100, progress, false)

        try {
            NotificationManagerCompat.from(this).notify(tripNotifId, builder.build())
        } catch (_: SecurityException) {
            // Permission not granted yet; will show once the user allows it.
        }
    }

    // ---- Pre-trip departure reminders --------------------------------------

    private fun ensureReminderChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(reminderChannelId) == null) {
                val channel = NotificationChannel(
                    reminderChannelId, "Trip Reminders", NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Pre-trip preparation reminders & departure alerts"
                    setShowBadge(true)
                    enableVibration(true)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun scheduleDepartureReminder(call: MethodCall) {
        val idStr = call.argument<String>("id") ?: "reminder_${System.currentTimeMillis()}"
        val tripId = call.argument<String>("tripId") ?: idStr
        val title = call.argument<String>("title") ?: "🚗 Trip Departure Reminder"
        val body = call.argument<String>("body") ?: "Your trip begins in 30 minutes. Time to get ready!"
        val destination = call.argument<String>("destination") ?: "Trip"
        val actionType = call.argument<String>("actionType") ?: "trip_start"
        val departureTime = call.argument<String>("departureTime") ?: ""
        val seconds = (call.argument<Double>("secondsFromNow") ?: 1.0).toLong()

        val nid = reminderBaseNotifId + Math.abs(idStr.hashCode() % 1000)
        val triggerAtMillis = System.currentTimeMillis() + (seconds * 1000L)

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val intent = Intent(this, TripAlarmReceiver::class.java).apply {
            putExtra("id", idStr)
            putExtra("tripId", tripId)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("destination", destination)
            putExtra("actionType", actionType)
            putExtra("departureTime", departureTime)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            nid,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (alarmManager != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                }
            } catch (se: SecurityException) {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        }
    }

    private fun cancelReminder(idStr: String) {
        val nid = reminderBaseNotifId + Math.abs(idStr.hashCode() % 1000)
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val intent = Intent(this, TripAlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            nid,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null && alarmManager != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        NotificationManagerCompat.from(this).cancel(nid)
    }
}
