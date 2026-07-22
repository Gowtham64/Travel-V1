// ============================================================================
// Android Auto — NavigationScreen scaffolding
// Renders the driver-safe navigation template: maneuver + distance + ETA banner.
// Fed by CarNavState, which the Flutter MethodChannel handler updates.
// ============================================================================

package io.github.gowtham64.travelapp.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.model.DateTimeWithZone
import java.util.concurrent.TimeUnit

/**
 * Simple observable holder the Flutter side pushes updates into via the
 * `com.travelapp.car` MethodChannel handler (see MainActivity additions in
 * README.md). The screen invalidates when it changes.
 */
object CarNavState {
    var isNavigating: Boolean = false
    var instruction: String = "Start navigation"
    var maneuverType: String = "straight"       // matches Dart ManeuverType.name
    var distanceMeters: Double = 0.0
    var remainingDistanceKm: Double = 0.0
    var remainingDurationMin: Int = 0

    private val listeners = mutableListOf<() -> Unit>()
    fun addListener(l: () -> Unit) { listeners.add(l) }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }
    fun notifyChanged() { listeners.forEach { it() } }
}

class NavigationScreen(carContext: CarContext) : Screen(carContext) {

    private val onChange: () -> Unit = { invalidate() }

    init {
        CarNavState.addListener(onChange)
        lifecycle.addObserver(androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_DESTROY) {
                CarNavState.removeListener(onChange)
            }
        })
    }

    override fun onGetTemplate(): Template {
        if (!CarNavState.isNavigating) {
            return NavigationTemplate.Builder()
                .setNavigationInfo(
                    RoutingInfo.Builder()
                        .setLoading(true)
                        .build()
                )
                .build()
        }

        val maneuver = Maneuver.Builder(mapManeuverType(CarNavState.maneuverType))
            .build()

        val step = Step.Builder(CarNavState.instruction)
            .setManeuver(maneuver)
            .build()

        val routingInfo = RoutingInfo.Builder()
            .setCurrentStep(
                step,
                Distance.create(CarNavState.distanceMeters, Distance.UNIT_METERS)
            )
            .build()

        val etaMillis = System.currentTimeMillis() +
            TimeUnit.MINUTES.toMillis(CarNavState.remainingDurationMin.toLong())
        val estimate = TravelEstimate.Builder(
            Distance.create(CarNavState.remainingDistanceKm, Distance.UNIT_KILOMETERS),
            DateTimeWithZone.create(etaMillis, java.util.TimeZone.getDefault())
        )
            .setRemainingTimeSeconds(TimeUnit.MINUTES.toSeconds(CarNavState.remainingDurationMin.toLong()))
            .build()

        return NavigationTemplate.Builder()
            .setNavigationInfo(routingInfo)
            .setDestinationTravelEstimate(estimate)
            .build()
    }

    /** Maps the Dart ManeuverType.name to Android Auto's Maneuver.TYPE_*. */
    private fun mapManeuverType(type: String): Int = when (type) {
        "turnLeft" -> Maneuver.TYPE_TURN_NORMAL_LEFT
        "turnRight" -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        "slightLeft" -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        "slightRight" -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        "uTurn" -> Maneuver.TYPE_U_TURN_LEFT
        "destination" -> Maneuver.TYPE_DESTINATION
        else -> Maneuver.TYPE_STRAIGHT
    }
}
