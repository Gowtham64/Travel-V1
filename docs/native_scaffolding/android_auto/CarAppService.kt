// ============================================================================
// Android Auto — CarAppService scaffolding
// Drop-in target: mobile/android/app/src/main/kotlin/io/github/gowtham64/travelapp/car/
// Package must match the directory. Requires the androidx.car.app dependency
// (see README.md) and the manifest additions (see AndroidManifest.additions.xml).
//
// This implements the CAR side of the `com.travelapp.car` MethodChannel contract
// defined in lib/services/car_platform_channel.dart:
//   - setRoute(start, end, waypoints, coordinates)
//   - updateNavigation(instruction, maneuverType, distance..., speed..., eta...)
//   - setNavigationState(isNavigating)
//
// NOTE: This is scaffolding. It has not been compiled here (no local Android
// SDK). Build it on a machine with the Android toolchain and iterate against the
// DHU. Wiring the MethodChannel <-> CarAppService (a cross-process bridge on
// Android Auto) is marked TODO where a shared singleton / bound service is needed.
// ============================================================================

package io.github.gowtham64.travelapp.car

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class TravelCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // For development. For production, allow-list only trusted hosts:
        // return HostValidator.Builder(applicationContext)
        //     .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
        //     .build()
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = TravelCarSession()
}

class TravelCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return NavigationScreen(carContext)
    }
}
