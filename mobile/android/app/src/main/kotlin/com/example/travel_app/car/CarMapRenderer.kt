package com.example.travel_app.car

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.util.LruCache
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Draws an actual slippy-map (OpenStreetMap raster tiles) onto the Android Auto
 * map surface, with the trek/route polyline and markers on top. Tiles are fetched
 * on a small thread pool and cached; when a tile arrives it calls [onTilesReady]
 * so the screen can redraw.
 */
class CarMapRenderer(private val onTilesReady: () -> Unit) {
    private companion object {
        const val TILE = 256.0
        const val UA = "VoyplanAndroidAuto/1.0 (contact: travel-app)"
    }

    private val cache = object : LruCache<String, Bitmap>(64) {}
    private val inFlight = HashSet<String>()
    private val io = Executors.newFixedThreadPool(4)

    // ---- Web Mercator helpers (world pixels at a given zoom) ----
    private fun lngToWorldX(lng: Double, z: Int): Double =
        (lng + 180.0) / 360.0 * (1 shl z) * TILE

    private fun latToWorldY(lat: Double, z: Int): Double {
        val s = sin(lat * Math.PI / 180.0).coerceIn(-0.9999, 0.9999)
        val y = 0.5 - ln((1 + s) / (1 - s)) / (4 * Math.PI)
        return y * (1 shl z) * TILE
    }

    /** Pick the highest zoom at which the route's bounds fit the drawable area. */
    private fun zoomForBounds(route: List<LatLngD>, w: Double, h: Double): Int {
        if (route.size < 2) return 13
        var minLat = 90.0; var maxLat = -90.0; var minLng = 180.0; var maxLng = -180.0
        for (p in route) {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLng = min(minLng, p.lng); maxLng = max(maxLng, p.lng)
        }
        for (z in 16 downTo 3) {
            val spanX = kotlin.math.abs(lngToWorldX(maxLng, z) - lngToWorldX(minLng, z))
            val spanY = kotlin.math.abs(latToWorldY(minLat, z) - latToWorldY(maxLat, z))
            if (spanX <= w * 0.9 && spanY <= h * 0.9) return z
        }
        return 3
    }

    /**
     * Render the map into [canvas] within [area], centred on [center] and framing
     * [route] if present. Missing tiles are fetched asynchronously.
     */
    fun draw(
        canvas: Canvas,
        area: Rect,
        center: LatLngD,
        route: List<LatLngD>,
        fixedZoom: Int? = null,
        bearingDeg: Double? = null,
    ) {
        val w = (area.width()).toDouble()
        val h = (area.height()).toDouble()
        if (w <= 0 || h <= 0) return

        val z = fixedZoom ?: zoomForBounds(route, w, h)
        val cwx = lngToWorldX(center.lng, z)
        val cwy = latToWorldY(center.lat, z)
        val cx = area.left + w / 2.0
        val cy = area.top + h / 2.0

        // World-pixel of the top-left corner of the drawable area.
        val originWX = cwx - (cx - area.left)
        val originWY = cwy - (cy - area.top)

        val maxTile = (1 shl z) - 1
        val txStart = kotlin.math.floor(originWX / TILE).toInt()
        val tyStart = kotlin.math.floor(originWY / TILE).toInt()
        val txEnd = kotlin.math.floor((originWX + w) / TILE).toInt()
        val tyEnd = kotlin.math.floor((originWY + h) / TILE).toInt()

        for (tx in txStart..txEnd) {
            for (ty in tyStart..tyEnd) {
                if (tx < 0 || ty < 0 || tx > maxTile || ty > maxTile) continue
                val key = "$z/$tx/$ty"
                val bmp = cache.get(key)
                val screenX = (tx * TILE - originWX + area.left).toFloat()
                val screenY = (ty * TILE - originWY + area.top).toFloat()
                if (bmp != null) {
                    canvas.drawBitmap(bmp, screenX, screenY, null)
                } else {
                    fetchTile(z, tx, ty, key)
                }
            }
        }

        // Convert a lat/lng to screen coords in the current frame.
        fun sx(lng: Double) = (lngToWorldX(lng, z) - originWX + area.left).toFloat()
        fun sy(lat: Double) = (latToWorldY(lat, z) - originWY + area.top).toFloat()

        if (route.size >= 2) {
            val line = Paint().apply {
                color = Color.rgb(46, 117, 182)
                strokeWidth = 12f
                style = Paint.Style.STROKE
                isAntiAlias = true
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            val path = Path()
            path.moveTo(sx(route[0].lng), sy(route[0].lat))
            for (i in 1 until route.size) path.lineTo(sx(route[i].lng), sy(route[i].lat))
            canvas.drawPath(path, line)

            val dot = Paint().apply { isAntiAlias = true }
            dot.color = Color.rgb(34, 197, 94)
            canvas.drawCircle(sx(route.first().lng), sy(route.first().lat), 16f, dot)
            dot.color = Color.rgb(239, 68, 68)
            canvas.drawCircle(sx(route.last().lng), sy(route.last().lat), 16f, dot)
        }

        // Vehicle marker at the current position.
        CarNavState.currentPosition()?.let {
            val px = sx(it.lng)
            val py = sy(it.lat)
            if (bearingDeg != null) {
                drawHeadingArrow(canvas, px, py, bearingDeg)
            } else {
                val ring = Paint().apply { color = Color.WHITE; isAntiAlias = true }
                canvas.drawCircle(px, py, 20f, ring)
                val fill = Paint().apply { color = Color.rgb(37, 99, 235); isAntiAlias = true }
                canvas.drawCircle(px, py, 14f, fill)
            }
        }
    }

    /** A Google-Maps-style directional chevron pointing along [bearingDeg]. */
    private fun drawHeadingArrow(canvas: Canvas, x: Float, y: Float, bearingDeg: Double) {
        canvas.save()
        canvas.rotate(bearingDeg.toFloat(), x, y)
        val ring = Paint().apply { color = Color.WHITE; isAntiAlias = true; style = Paint.Style.FILL }
        canvas.drawCircle(x, y, 26f, ring)
        val body = Paint().apply { color = Color.rgb(37, 99, 235); isAntiAlias = true; style = Paint.Style.FILL }
        val p = Path()
        p.moveTo(x, y - 22f)          // tip (points "up" before rotation = along bearing)
        p.lineTo(x - 15f, y + 16f)
        p.lineTo(x, y + 8f)
        p.lineTo(x + 15f, y + 16f)
        p.close()
        canvas.drawPath(p, body)
        canvas.restore()
    }

    private fun fetchTile(z: Int, x: Int, y: Int, key: String) {
        synchronized(inFlight) {
            if (inFlight.contains(key)) return
            inFlight.add(key)
        }
        io.execute {
            var bmp: Bitmap? = null
            try {
                val url = URL("https://tile.openstreetmap.org/$z/$x/$y.png")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000
                    readTimeout = 8000
                    setRequestProperty("User-Agent", UA)
                }
                conn.inputStream.use { bmp = BitmapFactory.decodeStream(it) }
                conn.disconnect()
            } catch (_: Exception) {
            }
            if (bmp != null) cache.put(key, bmp)
            synchronized(inFlight) { inFlight.remove(key) }
            if (bmp != null) onTilesReady()
        }
    }
}
