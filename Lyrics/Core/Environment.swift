import Foundation

struct AppEnvironment {
    var spotifyClientID: String

    static var `default`: AppEnvironment {
        let infoValue = (Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AppEnvironment(
            spotifyClientID: infoValue
        )
    }
}
