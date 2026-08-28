package com.example.travel_app.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

/** Holds the single navigation screen for the car session. */
class TravelSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = NavigationScreen(carContext)
}
