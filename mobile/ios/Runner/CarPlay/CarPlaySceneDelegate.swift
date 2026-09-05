import UIKit
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?
    var mapTemplate: CPMapTemplate?
    private var mapViewController: CarPlayMapViewController?
    private var isVoiceMuted: Bool = false

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        NSLog("VOYPLAN CarPlay: Scene connected successfully")
        self.interfaceController = interfaceController
        self.carWindow = window

        // 1. Initialize custom Map View Controller in CarPlay window
        let mapVC = CarPlayMapViewController()
        self.mapViewController = mapVC
        window.rootViewController = mapVC

        // 2. Build CPMapTemplate
        let mapTemplate = CPMapTemplate()
        mapTemplate.mapDelegate = self
        self.mapTemplate = mapTemplate
        CarPlayNavigationManager.shared.mapTemplate = mapTemplate

        // 3. Configure Map Buttons (Recenter, Overview, Mute)
        setupMapButtons(for: mapTemplate)

        // 4. Configure Navigation Bar Buttons (End Trip)
        setupNavigationBarButtons(for: mapTemplate)

        // 5. Present root template
        if #available(iOS 14.0, *) {
            interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)
        } else {
            interfaceController.setRootTemplate(mapTemplate, animated: false)
        }

        // 6. If a trip is already active on the phone, synchronize immediately
        if CarPlayNavigationManager.shared.isNavigating {
            CarPlayNavigationManager.shared.syncTripWithCarPlay()
            if let coords = CarPlayNavigationManager.shared.routeCoordinates as [CLLocationCoordinate2D]?,
               !coords.isEmpty {
                mapVC.updateRoute(
                    coordinates: coords,
                    waypoints: CarPlayNavigationManager.shared.waypoints,
                    fuelStops: CarPlayNavigationManager.shared.fuelStops
                )
            }
            if let loc = CarPlayNavigationManager.shared.currentLocation {
                mapVC.updateVehicleLocation(loc, bearing: CarPlayNavigationManager.shared.currentBearing)
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        NSLog("VOYPLAN CarPlay: Scene disconnected")
        CarPlayNavigationManager.shared.mapTemplate = nil
        CarPlayNavigationManager.shared.mapViewController = nil
        self.interfaceController = nil
        self.carWindow = nil
        self.mapTemplate = nil
        self.mapViewController = nil
    }

    // MARK: - Map Buttons Configuration

    private func setupMapButtons(for template: CPMapTemplate) {
        var buttons: [CPMapButton] = []

        // Recenter Button
        let recenterImage = UIImage(systemName: "location.fill") ?? UIImage()
        let recenterBtn = CPMapButton { [weak self] _ in
            self?.mapViewController?.recenterOnVehicle()
        }
        recenterBtn.image = recenterImage
        buttons.append(recenterBtn)

        // Overview / Fit Route Button
        let overviewImage = UIImage(systemName: "arrow.up.left.and.arrow.down.right") ?? UIImage()
        let overviewBtn = CPMapButton { [weak self] _ in
            self?.mapViewController?.zoomToOverview()
        }
        overviewBtn.image = overviewImage
        buttons.append(overviewBtn)

        // Voice Guidance Mute/Unmute Button
        let muteImage = UIImage(systemName: "speaker.wave.2.fill") ?? UIImage()
        let muteBtn = CPMapButton { [weak self] btn in
            guard let self = self else { return }
            let isMuted = CarPlayVoiceGuidance.shared.toggleMute()
            self.isVoiceMuted = isMuted
            btn.image = isMuted
                ? (UIImage(systemName: "speaker.slash.fill") ?? UIImage())
                : (UIImage(systemName: "speaker.wave.2.fill") ?? UIImage())
        }
        muteBtn.image = muteImage
        buttons.append(muteBtn)

        template.mapButtons = buttons
    }

    private func setupNavigationBarButtons(for template: CPMapTemplate) {
        // "End Trip" button in header bar
        let endTripButton = CPBarButton(type: .text) { _ in
            NSLog("VOYPLAN CarPlay: Driver tapped End Trip")
            CarPlayNavigationManager.shared.stopNavigation(fromCar: true)
        }
        endTripButton.title = "End Trip"
        template.trailingNavigationBarButtons = [endTripButton]
    }

    // MARK: - CPMapTemplateDelegate

    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {
        // User is panning the map
    }

    func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
        // Return to tracking vehicle
        mapViewController?.recenterOnVehicle()
    }
}
