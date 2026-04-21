import SwiftUI
import Foundation

struct NowPlayingView: View {
    @StateObject var viewModel: NowPlayingViewModel

    var body: some View {
        ZStack {
            dynamicBackground

            ScrollViewReader { proxy in
                VStack(spacing: 14) {
                    compactHeader
                    lyricsStage
                    playbackFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: viewModel.activeLyricLineID) { lineID in
                    guard let lineID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.stopProgressTicker()
            viewModel.stopPlaybackRefreshTicker()
        }
    }

    private var dynamicBackground: some View {
        ZStack {
            if let artworkURL = viewModel.playback?.track.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderBackdrop
                    case .empty:
                        placeholderBackdrop
                    @unknown default:
                        placeholderBackdrop
                    }
                }
            } else {
                placeholderBackdrop
            }
        }
        .ignoresSafeArea()
        .blur(radius: 52)
        .scaleEffect(1.2)
        .overlay {
            Rectangle()
                .fill(Color.black.opacity(0.36))
                .ignoresSafeArea()
        }
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.72))
                .ignoresSafeArea()
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            artworkThumbnail(size: 56, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.playback?.track.title ?? "Sin reproduccion")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(viewModel.playback?.track.artist ?? "Conecta Spotify para empezar")
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.86))
            }

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.toggleLike() }
            } label: {
                Image(systemName: viewModel.isTrackLiked ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(viewModel.isTrackLiked ? .pink : .white)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.playback == nil || viewModel.isTrackLikeLoading)

            Menu {
                Button {
                    viewModel.toggleLyricsBlur()
                } label: {
                    Label(
                        viewModel.isLyricsBlurEnabled ? "Lyrics blur effect ✓" : "Lyrics blur effect",
                        systemImage: "drop"
                    )
                }

                Section("Lyrics alignment") {
                    Button {
                        viewModel.setLyricsAlignment(.left)
                    } label: {
                        Label("align left", systemImage: viewModel.lyricsAlignment == .left ? "checkmark.text.line.first.and.arrowtriangle.forward" : "text.alignleft")
                    }

                    Button {
                        viewModel.setLyricsAlignment(.center)
                    } label: {
                        Label("align center", systemImage: viewModel.lyricsAlignment == .center ? "checkmark.text.line.first.and.arrowtriangle.forward" : "text.aligncenter")
                    }
                }

                Divider()

                Button {
                    Task { await viewModel.manualRefresh() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.horizontal")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private var lyricsStage: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let lines = viewModel.lyrics?.lines, !lines.isEmpty {
                    let activeIndex = lines.firstIndex(where: { $0.id == viewModel.activeLyricLineID })
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(
                            line: line,
                            index: index,
                            activeIndex: activeIndex
                        )
                        .id(line.id)
                    }
                } else if viewModel.isLoading {
                    ProgressView("Cargando letras...")
                        .foregroundStyle(.white)
                        .padding(.top, 24)
                } else {
                    Text(viewModel.errorMessage ?? "No hay letras disponibles.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var playbackFooter: some View {
        ZStack {
            HStack(spacing: 28) {
                Button {
                    Task { await viewModel.skipToPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.togglePlayPause() }
                } label: {
                    Image(systemName: (viewModel.playback?.isPlaying ?? false) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.skipToNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button {
                    viewModel.toggleTranslation()
                } label: {
                    Image(systemName: "character.arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(viewModel.isTranslationEnabled ? Color.blue : .white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .opacity(viewModel.isPerformingPlaybackAction ? 0.72 : 1)
        .disabled(viewModel.isPerformingPlaybackAction || viewModel.playback == nil)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private func artworkThumbnail(size: CGFloat, cornerRadius: CGFloat) -> some View {
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
                        placeholderArtwork
                    @unknown default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderBackdrop: some View {
        LinearGradient(
            colors: [Color(red: 0.18, green: 0.14, blue: 0.24), Color(red: 0.06, green: 0.07, blue: 0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.16))
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func lyricLineView(line: LyricsLine, index: Int, activeIndex: Int?) -> some View {
        let isActive = line.id == viewModel.activeLyricLineID
        let distance = lyricDistance(for: index, activeIndex: activeIndex)
        let display = lyricDisplay(for: line.text)
        let blurAmount = viewModel.isLyricsBlurEnabled ? blur(for: distance, isActive: isActive) : 0

        return Button {
            Task { await viewModel.seekToLyricLine(line) }
        } label: {
            VStack(alignment: viewModel.lyricsAlignment == .left ? .leading : .center, spacing: display.translation == nil ? 0 : 4) {
                Text(display.original)
                    .font(primaryLyricFont(isActive: isActive))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white.opacity(opacity(for: distance, isActive: isActive)))
                    .multilineTextAlignment(textAlignment)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)

                if viewModel.isTranslationEnabled, let translation = display.translation {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(opacity(for: distance, isActive: isActive) * 0.82))
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                }
            }
            .blur(radius: blurAmount)
            .scaleEffect(isActive ? 1 : 0.96, anchor: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(line.timestampMS == nil || viewModel.playback == nil)
        .padding(.vertical, 2)
    }

    private var frameAlignment: Alignment {
        viewModel.lyricsAlignment == .left ? .leading : .center
    }

    private var textAlignment: TextAlignment {
        viewModel.lyricsAlignment == .left ? .leading : .center
    }

    private func primaryLyricFont(isActive: Bool) -> Font {
        if isActive {
            return .system(size: 46, weight: .bold, design: .rounded)
        }
        return .system(size: 37, weight: .semibold, design: .rounded)
    }

    private func lyricDistance(for index: Int, activeIndex: Int?) -> Int {
        guard let activeIndex else { return 3 }
        return abs(index - activeIndex)
    }

    private func opacity(for distance: Int, isActive: Bool) -> Double {
        if isActive { return 1 }
        switch distance {
        case 0: return 0.94
        case 1: return 0.64
        case 2: return 0.44
        case 3: return 0.28
        default: return 0.2
        }
    }

    private func blur(for distance: Int, isActive: Bool) -> CGFloat {
        if isActive { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 1.2
        case 2: return 2.2
        case 3: return 3.2
        default: return 4.1
        }
    }

    private func lyricDisplay(for rawLine: String) -> (original: String, translation: String?) {
        let separators = [" / ", " | ", " — "]
        for separator in separators {
            let parts = rawLine.components(separatedBy: separator).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return (parts[0], parts[1])
            }
        }
        return (rawLine, nil)
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
