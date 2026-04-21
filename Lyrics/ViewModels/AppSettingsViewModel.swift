import Foundation
import Combine

@MainActor
final class AppSettingsViewModel: ObservableObject {
    @Published var selectedTheme: AppTheme = .system
    @Published var isSpotifyConnected = false
    @Published var authErrorMessage: String?

    private let authService: SpotifyAuthServiceProtocol

    init(authService: SpotifyAuthServiceProtocol) {
        self.authService = authService
        refreshConnectionStatus()
    }

    func spotifyAuthorizationURL() -> URL? {
        let url = authService.authorizationURL()
        if url != nil {
            authErrorMessage = nil
        } else {
            #if DEBUG
            let infoValue = (Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let envValue = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("[AppSettingsViewModel] spotifyAuthorizationURL returned nil - bundleClientID=\(masked(infoValue)) processEnvClientID=\(masked(envValue))")
            #endif
        }
        return url
    }

    func handleRedirectURL(_ url: URL) async {
        do {
            try await authService.handleRedirectURL(url)
            authErrorMessage = nil
        } catch {
            authErrorMessage = "No fue posible completar la autenticacion."
        }
        refreshConnectionStatus()
    }

    func refreshConnectionStatus() {
        isSpotifyConnected = authService.hasValidSession()
    }

    func disconnectSpotify() {
        authService.signOut()
        isSpotifyConnected = false
    }

    private func masked(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        if value.count <= 8 { return value }
        return "\(value.prefix(4))...\(value.suffix(4)) (len:\(value.count))"
    }
}
