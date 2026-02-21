import Foundation
import CoreLocation
import Combine

/// Manages geofencing for the workplace location. Fires events when user enters/exits the region.
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isInsideGeofence: Bool = false
    @Published var lastError: String?

    /// Callbacks for geofence transitions
    var onEnterRegion: (() -> Void)?
    var onExitRegion: (() -> Void)?

    private static let workplaceRegionIdentifier = "com.shopclock.workplace"

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    /// Enable background location updates. Call after authorization is granted.
    private func enableBackgroundUpdatesIfPossible() {
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] != nil {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
        }
    }

    // MARK: - Public API

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func requestCurrentLocation() {
        manager.requestLocation()
    }

    /// Start monitoring a geofence around the given coordinate
    func startMonitoring(latitude: Double, longitude: Double, radius: Double) {
        stopMonitoring()

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: min(radius, manager.maximumRegionMonitoringDistance),
            identifier: Self.workplaceRegionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true

        enableBackgroundUpdatesIfPossible()
        manager.startMonitoring(for: region)

        // Check if already inside
        manager.requestState(for: region)
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions {
            if region.identifier == Self.workplaceRegionIdentifier {
                manager.stopMonitoring(for: region)
            }
        }
    }

    var isMonitoring: Bool {
        manager.monitoredRegions.contains { $0.identifier == Self.workplaceRegionIdentifier }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.workplaceRegionIdentifier else { return }
        DispatchQueue.main.async {
            self.isInsideGeofence = true
            self.onEnterRegion?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.workplaceRegionIdentifier else { return }
        DispatchQueue.main.async {
            self.isInsideGeofence = false
            self.onExitRegion?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == Self.workplaceRegionIdentifier else { return }
        DispatchQueue.main.async {
            switch state {
            case .inside:
                self.isInsideGeofence = true
                self.onEnterRegion?()
            case .outside:
                self.isInsideGeofence = false
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        lastError = "Region monitoring failed: \(error.localizedDescription)"
    }
}
