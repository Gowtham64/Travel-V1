package com.example.travel_app.car

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Fetches nearby POIs by category from OpenStreetMap's Overpass API. */
object PoiRepository {
    private val io = Executors.newSingleThreadExecutor()

    // App category -> OSM amenity tag.
    private val AMENITY = mapOf(
        "fuel" to "fuel",
        "police" to "police",
        "fire" to "fire_station",
        "hospital" to "hospital",
        "restaurant" to "restaurant",
    )

    /**
     * Fetch up to ~24 nearby POIs of [category] within ~8km of ([lat],[lng]).
     * [onResult] is invoked on a background thread with a distance-sorted list
     * (empty on failure/none).
     */
    fun fetchNearby(category: String, lat: Double, lng: Double, onResult: (List<Poi>) -> Unit) {
        val amenity = AMENITY[category] ?: return onResult(emptyList())
        io.execute {
            val out = ArrayList<Poi>()
            try {
                val q =
                    "[out:json][timeout:20];(" +
                        "node[\"amenity\"=\"$amenity\"](around:8000,$lat,$lng);" +
                        "way[\"amenity\"=\"$amenity\"](around:8000,$lat,$lng);" +
                    ");out center 40;"
                val body = "data=" + URLEncoder.encode(q, "UTF-8")
                val url = URL("https://overpass-api.de/api/interpreter")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 12000
                    readTimeout = 20000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    setRequestProperty("User-Agent", "VoyplanAndroidAuto/1.0")
                }
                conn.outputStream.use { it.write(body.toByteArray()) }
                val text = conn.inputStream.bufferedReader().use { it.readText() }
                conn.disconnect()

                val els = JSONObject(text).optJSONArray("elements") ?: return@execute onResult(emptyList())
                val seen = HashSet<String>()
                for (i in 0 until els.length()) {
                    val el = els.optJSONObject(i) ?: continue
                    val tags = el.optJSONObject("tags")
                    val name = tags?.optString("name").takeUnless { it.isNullOrBlank() }
                        ?: category.replaceFirstChar { it.uppercase() }
                    val plat = if (el.has("lat")) el.optDouble("lat")
                        else el.optJSONObject("center")?.optDouble("lat") ?: continue
                    val plng = if (el.has("lon")) el.optDouble("lon")
                        else el.optJSONObject("center")?.optDouble("lon") ?: continue
                    val key = name.lowercase() + "@" + (plat * 1000).toInt() + "," + (plng * 1000).toInt()
                    if (!seen.add(key)) continue
                    out.add(Poi(name, plat, plng, haversineKm(lat, lng, plat, plng)))
                }
                out.sortBy { it.distanceKm }
            } catch (_: Exception) {
            }
            onResult(if (out.size > 24) out.subList(0, 24).toList() else out)
        }
    }

    private fun haversineKm(la1: Double, lo1: Double, la2: Double, lo2: Double): Double {
        val r = 6371.0
        val dLat = Math.toRadians(la2 - la1)
        val dLng = Math.toRadians(lo2 - lo1)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(la1)) * cos(Math.toRadians(la2)) * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
