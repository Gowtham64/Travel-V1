package com.example.travel_app.car

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import com.example.travel_app.R
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.TimeZone

import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.model.CarText

/**
 * The single Android Auto navigation screen. It renders the route onto the car's
 * map surface and shows a turn-by-turn card + ETA driven by [CarNavState], which
 * the Flutter app feeds over the `com.travelapp.car` MethodChannel.
 */
class NavigationScreen(carContext: CarContext) : Screen(carContext), SurfaceCallback {

    private var surface: Surface? = null
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private var visibleArea: Rect? = null

    private val navigationManager: NavigationManager by lazy {
        carContext.getCarService(NavigationManager::class.java)
    }
    private var isNavStartedWithManager = false

    // Post back to the main thread (getMainExecutor() needs API 28; minSdk is 23).
    private val mainHandler = Handler(Looper.getMainLooper())

    // Renders real OSM map tiles onto the surface; redraws as tiles arrive.
    private val mapRenderer = CarMapRenderer(onTilesReady = { mainHandler.post { renderMap() } })

    // Re-render + refresh the template whenever Flutter pushes new state.
    private val stateListener: () -> Unit = {
        mainHandler.post {
            syncNavigationManager()
            invalidate()
            renderMap()
        }
    }

    init {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(this)
        navigationManager.setNavigationManagerCallback(object : NavigationManagerCallback {
            override fun onStopNavigation() {
                CarNavState.requestStopNavigationFromCar()
            }
        })
        CarNavState.addListener(stateListener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarNavState.removeListener(stateListener)
                if (isNavStartedWithManager) {
                    try {
                        navigationManager.navigationEnded()
                        isNavStartedWithManager = false
                    } catch (_: Exception) {}
                }
            }
        })
    }

    private fun syncNavigationManager() {
        if (CarNavState.isNavigating) {
            if (!isNavStartedWithManager) {
                try {
                    navigationManager.navigationStarted()
                    isNavStartedWithManager = true
                } catch (_: Exception) {}
            }
        } else {
            if (isNavStartedWithManager) {
                try {
                    navigationManager.navigationEnded()
                    isNavStartedWithManager = false
                } catch (_: Exception) {}
            }
        }
    }

    // ---- Template (maneuver card + ETA) ----

    private fun carIcon(resId: Int): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, resId)).build()

    override fun onGetTemplate(): Template {
        val s = CarNavState

        // Top action strip: End Navigation (if navigating), Recenter, and Nearby search.
        val actionStripBuilder = ActionStrip.Builder()
        if (s.isNavigating) {
            actionStripBuilder.addAction(
                Action.Builder()
                    .setTitle("End Trip")
                    .setOnClickListener {
                        CarNavState.requestStopNavigationFromCar()
                    }
                    .build()
            )
        }
        actionStripBuilder.addAction(
            Action.Builder()
                .setIcon(carIcon(R.drawable.ic_nearby))
                .setTitle("Nearby")
                .setOnClickListener { screenManager.push(PoiCategoryScreen(carContext)) }
                .build()
        )
        actionStripBuilder.addAction(
            Action.Builder()
                .setTitle("Re-center")
                .setOnClickListener {
                    CarNavState.zoomOffset = 0
                    CarNavState.focusPoi = null
                    renderMap()
                }
                .build()
        )
        val actionStrip = actionStripBuilder.build()

        // Map action strip: zoom in / out.
        val mapActionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setIcon(carIcon(R.drawable.ic_zoom_in))
                    .setOnClickListener {
                        CarNavState.zoomOffset = (CarNavState.zoomOffset + 1).coerceAtMost(4)
                        renderMap()
                    }
                    .build()
            )
            .addAction(
                Action.Builder()
                    .setIcon(carIcon(R.drawable.ic_zoom_out))
                    .setOnClickListener {
                        CarNavState.zoomOffset = (CarNavState.zoomOffset - 1).coerceAtLeast(-6)
                        renderMap()
                    }
                    .build()
            )
            .build()

        val builder = NavigationTemplate.Builder()
            .setActionStrip(actionStrip)
            .setMapActionStrip(mapActionStrip)

        if (s.isNavigating) {
            val nextFuel = s.nextFuelStop
            val cue = when {
                nextFuel != null && s.instruction.contains("Fuel", ignoreCase = true) ->
                    "⛽ ${nextFuel.name} · ${nextFuel.fuelType.replaceFirstChar { it.uppercase() }}"
                s.instruction.isNotBlank() -> s.instruction
                else -> "Follow the highlighted route"
            }
            val stepBuilder = Step.Builder(cue)
                .setManeuver(Maneuver.Builder(maneuverType(s.maneuverType)).build())
            if (s.roadName.isNotBlank()) {
                stepBuilder.setRoad(s.roadName)
            }
            val step = stepBuilder.build()

            val routingInfo = RoutingInfo.Builder()
                .setCurrentStep(step, Distance.create(s.distanceMeters.coerceAtLeast(0.0), Distance.UNIT_METERS))
                .build()
            builder.setNavigationInfo(routingInfo)

            val arrivalMillis = System.currentTimeMillis() + s.remainingDurationMin * 60_000L
            val etaBuilder = TravelEstimate.Builder(
                Distance.create(s.remainingDistanceKm.coerceAtLeast(0.0), Distance.UNIT_KILOMETERS),
                DateTimeWithZone.create(arrivalMillis, TimeZone.getDefault()),
            ).setRemainingTimeSeconds((s.remainingDurationMin * 60L).coerceAtLeast(0))

            if (nextFuel != null) {
                etaBuilder.setTripText(
                    CarText.Builder("⛽ Next: ${nextFuel.name}").build()
                )
            } else if (s.destinationName.isNotBlank()) {
                etaBuilder.setTripText(
                    CarText.Builder("To ${s.destinationName}").build()
                )
            }
            builder.setDestinationTravelEstimate(etaBuilder.build())
        } else {
            val message = if (s.route.isNotEmpty()) {
                "Route preview ready. Tap Start on phone to navigate."
            } else {
                "Start a trip on your phone to navigate here"
            }
            builder.setNavigationInfo(MessageInfo.Builder(message).build())
        }
        return builder.build()
    }

    /** Map the Flutter ManeuverType enum name to a Car App maneuver constant. */
    private fun maneuverType(name: String): Int = when (name) {
        "turnLeft" -> Maneuver.TYPE_TURN_NORMAL_LEFT
        "turnRight" -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        "slightLeft" -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        "slightRight" -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        "uTurn" -> Maneuver.TYPE_U_TURN_LEFT
        "destination" -> Maneuver.TYPE_DESTINATION
        else -> Maneuver.TYPE_STRAIGHT
    }

    // ---- Map surface ----

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        surface = surfaceContainer.surface
        surfaceWidth = surfaceContainer.width
        surfaceHeight = surfaceContainer.height
        renderMap()
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = visibleArea
        renderMap()
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        surface = null
    }

    private fun renderMap() {
        val sf = surface ?: return
        if (!sf.isValid || surfaceWidth <= 0 || surfaceHeight <= 0) return

        val canvas: Canvas = try {
            sf.lockCanvas(null)
        } catch (e: Exception) {
            return
        } ?: return

        try {
            canvas.drawColor(Color.rgb(229, 227, 223)) // map paper tone under tiles

            val route = CarNavState.route
            // Fill the ENTIRE surface with the map; Android Auto floats its card
            // (the "Start a trip…" message / routing info) on top. visibleArea is
            // only a hint for where NOT to place critical content, not the map bounds.
            val area = Rect(0, 0, surfaceWidth, surfaceHeight)
            if (area.width() <= 0 || area.height() <= 0) return

            val livePos = CarNavState.currentPosition()
            if (CarNavState.isNavigating && livePos != null) {
                // Google-Maps-style: follow the vehicle, zoomed in, heading arrow.
                mapRenderer.draw(canvas, area, livePos, route, fixedZoom = 16, bearingDeg = CarNavState.bearing)
            } else {
                // Idle / overview: frame the whole route, else a sensible default.
                val center: LatLngD = when {
                    route.size >= 2 -> {
                        var minLat = 90.0; var maxLat = -90.0; var minLng = 180.0; var maxLng = -180.0
                        for (p in route) {
                            if (p.lat < minLat) minLat = p.lat
                            if (p.lat > maxLat) maxLat = p.lat
                            if (p.lng < minLng) minLng = p.lng
                            if (p.lng > maxLng) maxLng = p.lng
                        }
                        LatLngD((minLat + maxLat) / 2, (minLng + maxLng) / 2)
                    }
                    CarNavState.start != null -> CarNavState.start!!
                    else -> LatLngD(12.9716, 77.5946) // Bengaluru fallback
                }
                mapRenderer.draw(canvas, area, center, route)
            }
        } finally {
            try {
                sf.unlockCanvasAndPost(canvas)
            } catch (_: Exception) {
            }
        }
    }
}
