import Foundation
import CoreLocation

struct GardenPlace {
    var label: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String?
}

enum LocationError: LocalizedError {
    case denied
    case notFound
    case failed

    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Type your town or ZIP code instead, or allow location in Settings."
        case .notFound: return "Couldn't find that place. Try a town and state, or a ZIP code."
        case .failed: return "Couldn't get your location. Type your town or ZIP code instead."
        }
    }
}

/// Finds the garden's location once, from GPS or a typed town or ZIP code.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentPlace() async throws -> GardenPlace {
        let location = try await currentLocation()
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return GardenPlace(
            label: placemark.map(Self.label) ?? "My garden",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneID: placemark?.timeZone?.identifier
        )
    }

    func place(named text: String) async throws -> GardenPlace {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw LocationError.notFound }
        let results = (try? await CLGeocoder().geocodeAddressString(query)) ?? []
        guard let placemark = results.first, let location = placemark.location else { throw LocationError.notFound }
        return GardenPlace(
            label: Self.label(placemark),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneID: placemark.timeZone?.identifier
        )
    }

    private static func label(_ p: CLPlacemark) -> String {
        let parts = [p.locality ?? p.subAdministrativeArea, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (p.name ?? "My garden") : parts.joined(separator: ", ")
    }

    private func currentLocation() async throws -> CLLocation {
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: LocationError.failed)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(LocationError.failed)) }
    }
}
