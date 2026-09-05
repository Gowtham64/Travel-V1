package com.example.travel_app.car

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point Android Auto binds to. Declared in the manifest with the
 * `androidx.car.app.category.NAVIGATION` category so it appears as a navigation
 * app on the car head unit.
 */
class TravelCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // Allows Android Auto head units and Desktop Head Unit (DHU) to connect seamlessly.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = TravelSession()
}
