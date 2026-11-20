import Foundation
import GardenCore

/// Fetches history and forecast from Open-Meteo (free, no key) straight from the phone.
enum WeatherService {
    static func fetch(latitude: Double, longitude: Double, pastDays: Int) async throws -> WeatherReport {
        var request = URLRequest(url: OpenMeteo.forecastURL(latitude: latitude, longitude: longitude, pastDays: pastDays))
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
            throw URLError(.badServerResponse)
        }
        return try OpenMeteo.parse(data, fetchedAt: Date())
    }
}
