import SwiftUI

struct MainTabView: View {
    @StateObject var router: AppRouter
    @StateObject var settingsViewModel: AppSettingsViewModel
    @StateObject var carPlaySettingsViewModel: CarPlaySettingsViewModel
    @StateObject var nowPlayingViewModel: NowPlayingViewModel

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                CarPlayWidgetSettingsView(viewModel: carPlaySettingsViewModel)
            }
            .tabItem {
                Label("CarPlay", systemImage: "car.fill")
            }
            .tag(AppRouter.Tab.carPlaySettings)

            NavigationStack {
                NowPlayingView(viewModel: nowPlayingViewModel)
            }
            .tabItem {
                Label("Reproductor", systemImage: "music.note")
            }
            .tag(AppRouter.Tab.nowPlaying)

            NavigationStack {
                SettingsView(viewModel: settingsViewModel)
            }
            .tabItem {
                Label("Config", systemImage: "gearshape.fill")
            }
            .tag(AppRouter.Tab.settings)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .glassScreenBackground()
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView.preview
    }
}

private extension MainTabView {
    static var preview: MainTabView {
        let tokenStore = TokenStore()
        let authService = SpotifyAuthService(
            environment: .default,
            tokenStore: tokenStore
        )
        return MainTabView(
            router: AppRouter(),
            settingsViewModel: AppSettingsViewModel(
                authService: authService
            ),
            carPlaySettingsViewModel: CarPlaySettingsViewModel(),
            nowPlayingViewModel: NowPlayingViewModel(
                playbackService: SpotifyPlaybackService(authService: authService),
                lyricsService: LyricsService()
            )
        )
    }
}
