import Foundation
import GardenCore

/// Talks to the coach backend (backend/src/router.ts). Without an endpoint the app is in demo mode.
struct CoachService {
    let endpoint: CoachEndpoint?

    var isLive: Bool { endpoint != nil }

    func health() async throws -> HealthResponse {
        let (data, status) = try await send("v1/health", body: nil, timeout: 20)
        return try CoachEndpoint.decode(HealthResponse.self, data: data, status: status)
    }

    func chat(_ request: CoachRequest) async throws -> CoachResponse {
        let (data, status) = try await send("v1/coach", body: try encode(request), timeout: 150)
        return try CoachEndpoint.decode(CoachResponse.self, data: data, status: status)
    }

    func diagnose(_ request: DiagnoseRequest) async throws -> Diagnosis {
        let (data, status) = try await send("v1/diagnose", body: try encode(request), timeout: 180)
        return try CoachEndpoint.decode(DiagnoseResponse.self, data: data, status: status).diagnosis
    }

    func phrase(_ drafts: [NudgeDraft]) async throws -> [NudgePhrasing] {
        let (data, status) = try await send("v1/nudges/phrase", body: try encode(PhraseRequest(nudges: drafts)), timeout: 60)
        return try CoachEndpoint.decode(PhraseResponse.self, data: data, status: status).phrasings
    }

    /// MP3 audio of the text in David's cloned voice.
    func speak(_ text: String) async throws -> Data {
        let (data, status) = try await send("v1/speak", body: try encode(SpeakRequest(text: text)), timeout: 60)
        guard (200..<300).contains(status) else {
            // Throws the server's error.
            _ = try CoachEndpoint.decode(HealthResponse.self, data: data, status: status)
            throw CoachAPIError.badResponse
        }
        return data
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try GardenSnapshot.makeEncoder().encode(value)
    }

    private func send(_ path: String, body: Data?, timeout: TimeInterval) async throws -> (Data, Int) {
        guard let endpoint = endpoint else { throw CoachAPIError.notConfigured }
        let request = endpoint.request(path: path, body: body, timeout: timeout)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            throw CoachAPIError.network(error.localizedDescription)
        }
    }
}
