import Foundation

struct AppEnvironment {
    var spotifyClientID: String

    static var `default`: AppEnvironment {
        AppEnvironment(
            spotifyClientID: Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
        )
    }
}
