package com.example.travel_app

import com.example.travel_app.car.CarNavState
import com.example.travel_app.car.LatLngD
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        CarNavState.isNavigating = true
                        CarNavState.notifyChanged()
                        result.success(null)
                    }
                    "setNavigationState" -> {
                        CarNavState.isNavigating = call.argument<Boolean>("isNavigating") ?: false
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
}
