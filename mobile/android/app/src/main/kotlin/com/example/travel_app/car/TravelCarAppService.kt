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
        // In debug builds allow any host so the Desktop Head Unit (DHU) can connect.
        // Release builds must validate against the known Android Auto/Automotive hosts.
        return if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = TravelSession()
}
