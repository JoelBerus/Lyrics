import Foundation
import Combine

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published var playback: PlaybackState?
    @Published var lyrics: LyricsPayload?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentProgressMS: Int = 0
    @Published var activeLyricLineID: String?

    private let playbackService: SpotifyPlaybackServiceProtocol
    private let lyricsService: LyricsServiceProtocol
    private var progressCancellable: AnyCancellable?

    init(
        playbackService: SpotifyPlaybackServiceProtocol,
        lyricsService: LyricsServiceProtocol
    ) {
        self.playbackService = playbackService
        self.lyricsService = lyricsService
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await playbackService.fetchNowPlaying()
            self.playback = playback
            self.currentProgressMS = playback.progressMS
            startProgressTicker()

            do {
                let lyrics = try await lyricsService.fetchLyrics(for: playback.track)
                self.lyrics = lyrics
                updateActiveLyricLine()
                publishCarPlaySnapshot()
            } catch {
                self.lyrics = LyricsPayload(
                    isSynced: false,
                    lines: [LyricsLine(timestampMS: nil, text: "No encontramos letras para esta canción.")]
                )
                self.activeLyricLineID = nil
                publishCarPlaySnapshot()
            }
        } catch {
            errorMessage = "No pudimos cargar la canción actual."
            stopProgressTicker()
            NowPlayingSharedState.shared.update(snapshot: nil)
        }
    }

    func stopProgressTicker() {
        progressCancellable?.cancel()
        progressCancellable = nil
    }
}

private extension NowPlayingViewModel {
    func startProgressTicker() {
        stopProgressTicker()
        progressCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let playback = self.playback else { return }
                guard playback.isPlaying else { return }

                let nextProgress = min(currentProgressMS + 500, playback.track.durationMS)
                currentProgressMS = nextProgress
                updateActiveLyricLine()
                publishCarPlaySnapshot()
            }
    }

    func updateActiveLyricLine() {
        guard let lyrics, lyrics.isSynced else {
            activeLyricLineID = nil
            return
        }

        let syncedLines = lyrics.lines.filter { $0.timestampMS != nil }
        guard !syncedLines.isEmpty else {
            activeLyricLineID = nil
            return
        }

        let currentLine = syncedLines.last { line in
            (line.timestampMS ?? Int.max) <= currentProgressMS
        }
        activeLyricLineID = currentLine?.id
    }

    func publishCarPlaySnapshot() {
        guard let playback, let lyrics, !lyrics.lines.isEmpty else {
            NowPlayingSharedState.shared.update(snapshot: nil)
            return
        }

        let currentLineText: String
        let nextLineText: String?

        if lyrics.isSynced {
            if let activeID = activeLyricLineID,
               let currentIndex = lyrics.lines.firstIndex(where: { $0.id == activeID }) {
                currentLineText = lyrics.lines[currentIndex].text
                let nextIndex = lyrics.lines.index(after: currentIndex)
                nextLineText = nextIndex < lyrics.lines.endIndex ? lyrics.lines[nextIndex].text : nil
            } else {
                currentLineText = lyrics.lines[0].text
                nextLineText = lyrics.lines.count > 1 ? lyrics.lines[1].text : nil
            }
        } else {
            currentLineText = lyrics.lines[0].text
            nextLineText = lyrics.lines.count > 1 ? lyrics.lines[1].text : nil
        }

        let snapshot = CarPlayLyricsSnapshot(
            trackTitle: playback.track.title,
            artist: playback.track.artist,
            currentLine: currentLineText,
            nextLine: nextLineText,
            isPlaying: playback.isPlaying
        )
        NowPlayingSharedState.shared.update(snapshot: snapshot)
    }
}
