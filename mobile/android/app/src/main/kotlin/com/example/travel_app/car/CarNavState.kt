package com.example.travel_app.car

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** A lat/lng pair. */
data class LatLngD(val lat: Double, val lng: Double)

/**
 * Process-wide bridge between the Flutter engine (which pushes route + maneuver
 * + telemetry over the `com.travelapp.car` MethodChannel) and the Android Auto
 * [NavigationScreen]. Both live in the same app process, so a singleton is the
 * simplest reliable channel. All access is on the main thread (MethodChannel
 * handlers and the car Screen both run there).
 */
object CarNavState {
    @Volatile var isNavigating: Boolean = false

    var start: LatLngD? = null
    var end: LatLngD? = null
    var waypoints: List<LatLngD> = emptyList()
    var route: List<LatLngD> = emptyList()

    // Live maneuver + telemetry (updated each guidance tick from Flutter).
    var instruction: String = ""
    var maneuverType: String = "straight"
    var distanceMeters: Double = 0.0
    var formattedDistance: String = ""
    var speedKmh: Double = 0.0
    var remainingDistanceKm: Double = 0.0
    var remainingDurationMin: Int = 0
    var formattedEta: String = ""

    private val listeners = mutableListOf<() -> Unit>()

    fun addListener(l: () -> Unit) { listeners.add(l) }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }

    /** Notify the car screen that state changed so it can re-render. */
    fun notifyChanged() {
        // Copy to avoid concurrent-modification if a listener unregisters.
        listeners.toList().forEach { it() }
    }

    /** Total length of the current route polyline, in km. */
    fun routeLengthKm(): Double {
        var total = 0.0
        for (i in 1 until route.size) total += haversineKm(route[i - 1], route[i])
        return total
    }

    /**
     * Estimate the current position along the route from how far is left. We only
     * receive remaining distance (not a live GPS fix) from Flutter, so we walk the
     * polyline to the point at (total - remaining). Returns null if unknown.
     */
    fun estimatedPosition(): LatLngD? {
        if (route.size < 2) return null
        val total = routeLengthKm()
        if (total <= 0) return route.firstOrNull()
        val travelled = (total - remainingDistanceKm).coerceIn(0.0, total)
        var acc = 0.0
        for (i in 1 until route.size) {
            val seg = haversineKm(route[i - 1], route[i])
            if (acc + seg >= travelled) {
                val t = if (seg <= 0) 0.0 else (travelled - acc) / seg
                return LatLngD(
                    route[i - 1].lat + (route[i].lat - route[i - 1].lat) * t,
                    route[i - 1].lng + (route[i].lng - route[i - 1].lng) * t,
                )
            }
            acc += seg
        }
        return route.last()
    }

    private fun haversineKm(a: LatLngD, b: LatLngD): Double {
        val r = 6371.0
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLng = Math.toRadians(b.lng - a.lng)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
