import SwiftUI
import Foundation

struct NowPlayingView: View {
    @StateObject var viewModel: NowPlayingViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    lyricsCard
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: viewModel.activeLyricLineID) { lineID in
                guard let lineID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
        }
        .navigationTitle("Reproductor")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.manualRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.stopProgressTicker()
            viewModel.stopPlaybackRefreshTicker()
        }
    }

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    artworkView

                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.playback?.track.title ?? "Sin reproducción")
                            .font(.title3.weight(.semibold))
                        Text(viewModel.playback?.track.artist ?? "Conecta Spotify para empezar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Progreso: \(formattedTime(viewModel.currentProgressMS))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.manualRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.title3)
                    }
                }

                HStack(spacing: 24) {
                    Button {
                        Task { await viewModel.skipToPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.togglePlayPause() }
                    } label: {
                        Image(systemName: (viewModel.playback?.isPlaying ?? false) ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.skipToNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .opacity(viewModel.isPerformingPlaybackAction ? 0.6 : 1)
                .disabled(viewModel.isPerformingPlaybackAction || viewModel.playback == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var artworkView: some View {
        Group {
            if let artworkURL = viewModel.playback?.track.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderArtwork
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var lyricsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Letras")
                    .font(.headline)
                if let lines = viewModel.lyrics?.lines, !lines.isEmpty {
                    ForEach(lines) { line in
                        Text(line.text)
                            .fontWeight(viewModel.activeLyricLineID == line.id ? .semibold : .regular)
                            .foregroundStyle(viewModel.activeLyricLineID == line.id ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(Color.white.opacity(viewModel.activeLyricLineID == line.id ? 0.15 : 0)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                } else if viewModel.isLoading {
                    ProgressView("Cargando letras...")
                } else {
                    Text(viewModel.errorMessage ?? "No hay letras disponibles.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedTime(_ milliseconds: Int) -> String {
        let totalSeconds = max(milliseconds / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        let tokenStore = TokenStore()
        let authService = SpotifyAuthService(environment: .default, tokenStore: tokenStore)
        NowPlayingView(
            viewModel: NowPlayingViewModel(
                playbackService: SpotifyPlaybackService(authService: authService),
                lyricsService: LyricsService()
            )
        )
    }
}
