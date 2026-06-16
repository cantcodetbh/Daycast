import CoreLocation
import Foundation

@MainActor
final class DaycastLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func currentLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            try await requestAuthorization()
        case .restricted, .denied:
            throw CLError(.denied)
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw CLError(.denied)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationContinuation?.resume(throwing: CancellationError())
                locationContinuation = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in
                self.locationContinuation?.resume(throwing: CancellationError())
                self.locationContinuation = nil
                self.manager.stopUpdatingLocation()
            }
        }
    }

    private func requestAuthorization() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation?.resume(throwing: CancellationError())
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        } onCancel: {
            Task { @MainActor in
                self.authorizationContinuation?.resume(throwing: CancellationError())
                self.authorizationContinuation = nil
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                authorizationContinuation?.resume()
                authorizationContinuation = nil
            case .restricted, .denied:
                authorizationContinuation?.resume(throwing: CLError(.denied))
                authorizationContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                authorizationContinuation?.resume(throwing: CLError(.denied))
                authorizationContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                locationContinuation?.resume(throwing: CLError(.locationUnknown))
                locationContinuation = nil
                return
            }

            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
