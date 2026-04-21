import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: AppSettingsViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.orange.opacity(0.25), .pink.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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
                        Button {
                            Task {
                                if viewModel.spotifyAuthorizationURL() == nil {
                                    viewModel.authErrorMessage = "Configura SPOTIFY_CLIENT_ID en Info.plist."
                                    return
                                }
                                await viewModel.connectSpotify()
                            }
                        } label: {
                            if viewModel.isAuthorizing {
                                ProgressView()
                            } else {
                                Text("Conectar con Spotify")
                            }
                        }
                        .disabled(viewModel.isAuthorizing)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollContentBackground(.hidden)
        }
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
