import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: AppSettingsViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Spotify") {
                Toggle("Conectado", isOn: $viewModel.isSpotifyConnected)
                    .disabled(true)
                if let authErrorMessage = viewModel.authErrorMessage {
                    Text(authErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if viewModel.isSpotifyConnected {
                    Button("Desconectar") {
                        viewModel.disconnectSpotify()
                    }
                } else {
                    Button("Conectar con Spotify") {
                        guard let url = viewModel.spotifyAuthorizationURL() else {
                            viewModel.authErrorMessage = "Configura SPOTIFY_CLIENT_ID en Info.plist."
                            return
                        }
                        openURL(url)
                    }
                }
            }

            Section("Tema") {
                Picker("Apariencia", selection: $viewModel.selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.25), .pink.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Configuración")
        .onAppear {
            viewModel.refreshConnectionStatus()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            viewModel: AppSettingsViewModel(
                authService: SpotifyAuthService(
                    environment: .default,
                    tokenStore: TokenStore()
                )
            )
        )
    }
}
