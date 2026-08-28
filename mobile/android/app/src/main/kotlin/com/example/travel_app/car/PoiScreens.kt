package com.example.travel_app.car

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** First screen of the "Nearby" flow: pick a category. */
class PoiCategoryScreen(carContext: CarContext) : Screen(carContext) {
    private val categories = listOf(
        "fuel" to "Fuel",
        "police" to "Police",
        "fire" to "Fire station",
        "hospital" to "Hospital",
        "restaurant" to "Restaurant",
    )

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for ((key, label) in categories) {
            list.addItem(
                Row.Builder()
                    .setTitle(label)
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(PoiResultsScreen(carContext, key, label)) }
                    .build()
            )
        }
        return ListTemplate.Builder()
            .setHeaderAction(Action.BACK)
            .setTitle("Nearby")
            .setSingleList(list.build())
            .build()
    }
}

/** Second screen: fetch and list nearby places for the chosen category. */
class PoiResultsScreen(
    carContext: CarContext,
    private val category: String,
    private val label: String,
) : Screen(carContext) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var results: List<Poi>? = null // null = still loading

    init {
        val here = CarNavState.currentPosition() ?: CarNavState.start ?: LatLngD(12.9716, 77.5946)
        PoiRepository.fetchNearby(category, here.lat, here.lng) { list ->
            mainHandler.post {
                results = list
                invalidate()
            }
        }
    }

    override fun onGetTemplate(): Template {
        val r = results
            ?: return ListTemplate.Builder()
                .setHeaderAction(Action.BACK)
                .setTitle("$label nearby")
                .setLoading(true)
                .build()

        val list = ItemList.Builder()
        if (r.isEmpty()) {
            list.setNoItemsMessage("No $label found nearby")
        } else {
            // Respect the host's list-length limit so build() can't throw.
            val limit = try {
                carContext.getCarService(ConstraintManager::class.java)
                    .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            } catch (_: Exception) { 6 }
            for (poi in r.take(limit)) {
                list.addItem(
                    Row.Builder()
                        .setTitle(poi.name)
                        .addText(String.format("%.1f km away", poi.distanceKm))
                        .setOnClickListener {
                            // Mark it on the map and return to the navigation screen.
                            CarNavState.focusPoi = LatLngD(poi.lat, poi.lng)
                            CarNavState.notifyChanged()
                            screenManager.popToRoot()
                        }
                        .build()
                )
            }
        }
        return ListTemplate.Builder()
            .setHeaderAction(Action.BACK)
            .setTitle("$label nearby")
            .setSingleList(list.build())
            .build()
    }
}
