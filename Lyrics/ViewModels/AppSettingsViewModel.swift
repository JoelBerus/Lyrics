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
}
