import SwiftUI

struct AppContainerView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @StateObject private var carPlaySettingsViewModel = CarPlaySettingsViewModel()
    @StateObject private var nowPlayingViewModel: NowPlayingViewModel

    init(environment: AppEnvironment = .default) {
        let tokenStore = TokenStore()
        let authService = SpotifyAuthService(environment: environment, tokenStore: tokenStore)
        let playbackService = SpotifyPlaybackService(authService: authService)
        let lyricsService = LyricsService()

        _settingsViewModel = StateObject(wrappedValue: AppSettingsViewModel(authService: authService))
        _nowPlayingViewModel = StateObject(
            wrappedValue: NowPlayingViewModel(
                playbackService: playbackService,
                lyricsService: lyricsService
            )
        )
    }

    var body: some View {
        MainTabView(
            router: router,
            settingsViewModel: settingsViewModel,
            carPlaySettingsViewModel: carPlaySettingsViewModel,
            nowPlayingViewModel: nowPlayingViewModel
        )
        .preferredColorScheme(settingsViewModel.selectedTheme.colorScheme)
    }
}

struct AppContainerView_Previews: PreviewProvider {
    static var previews: some View {
        AppContainerView()
    }
}
