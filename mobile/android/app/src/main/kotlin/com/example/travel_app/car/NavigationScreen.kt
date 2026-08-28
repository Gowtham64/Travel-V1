package com.example.travel_app.car

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.TimeZone

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

    // Post back to the main thread (getMainExecutor() needs API 28; minSdk is 23).
    private val mainHandler = Handler(Looper.getMainLooper())

    // Re-render + refresh the template whenever Flutter pushes new state.
    private val stateListener: () -> Unit = {
        mainHandler.post {
            invalidate()
            renderMap()
        }
    }

    init {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(this)
        CarNavState.addListener(stateListener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarNavState.removeListener(stateListener)
            }
        })
    }

    // ---- Template (maneuver card + ETA) ----

    override fun onGetTemplate(): Template {
        val actionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("Re-center")
                    .setOnClickListener { renderMap() }
                    .build()
            )
            .build()

        val builder = NavigationTemplate.Builder().setActionStrip(actionStrip)

        val s = CarNavState
        if (s.isNavigating) {
            val cue = s.instruction.ifBlank { "Continue" }
            val step = Step.Builder(cue)
                .setManeuver(Maneuver.Builder(maneuverType(s.maneuverType)).build())
                .build()
            val routingInfo = RoutingInfo.Builder()
                .setCurrentStep(step, Distance.create(s.distanceMeters.coerceAtLeast(0.0), Distance.UNIT_METERS))
                .build()
            builder.setNavigationInfo(routingInfo)

            val arrivalMillis = System.currentTimeMillis() + s.remainingDurationMin * 60_000L
            val eta = TravelEstimate.Builder(
                Distance.create(s.remainingDistanceKm.coerceAtLeast(0.0), Distance.UNIT_KILOMETERS),
                DateTimeWithZone.create(arrivalMillis, TimeZone.getDefault()),
            )
                .setRemainingTimeSeconds((s.remainingDurationMin * 60L).coerceAtLeast(0))
                .build()
            builder.setDestinationTravelEstimate(eta)
        } else {
            builder.setNavigationInfo(
                MessageInfo.Builder("Start a trip on your phone to navigate here").build()
            )
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
            canvas.drawColor(Color.rgb(14, 17, 22)) // matches the app's dark ground

            val route = CarNavState.route
            val area = visibleArea ?: Rect(0, 0, surfaceWidth, surfaceHeight)
            val pad = 40f
            val left = area.left + pad
            val top = area.top + pad
            val right = area.right - pad
            val bottom = area.bottom - pad
            if (right <= left || bottom <= top) return

            if (route.size < 2) {
                val hint = Paint().apply {
                    color = Color.argb(150, 255, 255, 255)
                    textSize = 34f
                    isAntiAlias = true
                }
                canvas.drawText("No active route", left, (top + bottom) / 2f, hint)
                return
            }

            // Fit the route's lat/lng bounds into the drawable area (equirectangular).
            var minLat = Double.MAX_VALUE; var maxLat = -Double.MAX_VALUE
            var minLng = Double.MAX_VALUE; var maxLng = -Double.MAX_VALUE
            for (p in route) {
                if (p.lat < minLat) minLat = p.lat
                if (p.lat > maxLat) maxLat = p.lat
                if (p.lng < minLng) minLng = p.lng
                if (p.lng > maxLng) maxLng = p.lng
            }
            val latSpan = (maxLat - minLat).coerceAtLeast(1e-6)
            val lngSpan = (maxLng - minLng).coerceAtLeast(1e-6)
            val w = right - left
            val h = bottom - top
            // Preserve aspect ratio so the route isn't stretched.
            val scale = minOf(w / lngSpan.toFloat(), h / latSpan.toFloat())
            val offsetX = left + (w - lngSpan.toFloat() * scale) / 2f
            val offsetY = top + (h - latSpan.toFloat() * scale) / 2f
            fun sx(lng: Double) = offsetX + ((lng - minLng).toFloat() * scale)
            fun sy(lat: Double) = offsetY + ((maxLat - lat).toFloat() * scale) // flip Y

            // Route polyline.
            val linePaint = Paint().apply {
                color = Color.rgb(96, 165, 250) // accentLight
                strokeWidth = 10f
                style = Paint.Style.STROKE
                isAntiAlias = true
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            val path = android.graphics.Path()
            path.moveTo(sx(route[0].lng), sy(route[0].lat))
            for (i in 1 until route.size) path.lineTo(sx(route[i].lng), sy(route[i].lat))
            canvas.drawPath(path, linePaint)

            // Start (green) and destination (red) markers.
            val dot = Paint().apply { isAntiAlias = true }
            CarNavState.start?.let { dot.color = Color.rgb(34, 197, 94); canvas.drawCircle(sx(it.lng), sy(it.lat), 14f, dot) }
            CarNavState.end?.let { dot.color = Color.rgb(239, 68, 68); canvas.drawCircle(sx(it.lng), sy(it.lat), 14f, dot) }

            // Estimated current position (blue) with a white ring.
            CarNavState.estimatedPosition()?.let {
                val ring = Paint().apply { color = Color.WHITE; isAntiAlias = true }
                canvas.drawCircle(sx(it.lng), sy(it.lat), 18f, ring)
                dot.color = Color.rgb(37, 99, 235)
                canvas.drawCircle(sx(it.lng), sy(it.lat), 13f, dot)
            }
        } finally {
            try {
                sf.unlockCanvasAndPost(canvas)
            } catch (_: Exception) {
            }
        }
    }
}
