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

class MainActivity : FlutterActivity() {

    private val tripNotifId = 4201
    private val tripChannelId = "trip_progress"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Live trip-progress notification (lock screen + shade), driven from
        // TripNotificationService (Dart). Native so iOS can stay on SPM.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.travelapp.notification")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    else -> result.notImplemented()
                }
            }

        // Receives route + maneuver + telemetry from CarPlatformChannel (Dart) and
        // feeds the Android Auto navigation screen via the shared CarNavState.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.travelapp.car")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRoute" -> {
                        CarNavState.start = parsePoint(call.argument("start"))
                        CarNavState.end = parsePoint(call.argument("end"))
                        CarNavState.waypoints = parseList(call.argument("waypoints"))
                        CarNavState.route = parseList(call.argument("coordinates"))
                        CarNavState.notifyChanged()
                        result.success(null)
                    }
                    "updateNavigation" -> {
                        CarNavState.instruction = call.argument<String>("instruction") ?: ""
                        CarNavState.maneuverType = call.argument<String>("maneuverType") ?: "straight"
                        CarNavState.distanceMeters = num(call.argument("distanceMeters"))
                        CarNavState.formattedDistance = call.argument<String>("formattedDistance") ?: ""
                        CarNavState.speedKmh = num(call.argument("speedKmh"))
                        CarNavState.remainingDistanceKm = num(call.argument("remainingDistanceKm"))
                        CarNavState.remainingDurationMin = num(call.argument("remainingDurationMin")).toInt()
                        CarNavState.formattedEta = call.argument<String>("formattedEta") ?: ""
                        // Live position + heading (may be absent on some ticks).
                        CarNavState.curLat = (call.argument("currentLat") as? Number)?.toDouble() ?: CarNavState.curLat
                        CarNavState.curLng = (call.argument("currentLng") as? Number)?.toDouble() ?: CarNavState.curLng
                        CarNavState.bearing = (call.argument("bearingDeg") as? Number)?.toDouble() ?: CarNavState.bearing
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
                        }
                        CarNavState.notifyChanged()
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
}
