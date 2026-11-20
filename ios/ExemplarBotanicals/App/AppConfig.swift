import Foundation
import GardenCore

/// Values the build puts in Info.plist from Config/App.xcconfig and Secrets.xcconfig.
struct AppConfig {
    /// Where the coach backend lives; nil means demo mode.
    let endpoint: CoachEndpoint?
    /// The coach's first name ("David").
    let coachName: String

    static func load(bundle: Bundle = .main) -> AppConfig {
        let info = bundle.infoDictionary ?? [:]
        let host = info["EBBackendHost"] as? String
        let secret = info["EBAppSecret"] as? String
        let rawName = ((info["EBCoachName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.isEmpty || rawName.contains("$(") ? "David" : rawName
        return AppConfig(endpoint: CoachEndpoint(host: host, secret: secret), coachName: name)
    }
}
