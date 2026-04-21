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
    @Published var isPerformingPlaybackAction = false

    private let playbackService: SpotifyPlaybackServiceProtocol
    private let lyricsService: LyricsServiceProtocol
    private var progressCancellable: AnyCancellable?
    private var playbackRefreshCancellable: AnyCancellable?

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
            try await refreshPlaybackState(forceLyricsReload: true)
            startProgressTicker()
            startPlaybackRefreshTicker()
        } catch {
            errorMessage = "No pudimos cargar la canción actual."
            stopProgressTicker()
            stopPlaybackRefreshTicker()
            NowPlayingSharedState.shared.update(snapshot: nil)
        }
    }

    func stopProgressTicker() {
        progressCancellable?.cancel()
        progressCancellable = nil
    }

    func stopPlaybackRefreshTicker() {
        playbackRefreshCancellable?.cancel()
        playbackRefreshCancellable = nil
    }

    func manualRefresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await refreshPlaybackState(forceLyricsReload: false)
            errorMessage = nil
        } catch {
            errorMessage = "No pudimos actualizar la reproduccion."
        }
    }

    func togglePlayPause() async {
        guard let playback else { return }
        isPerformingPlaybackAction = true
        defer { isPerformingPlaybackAction = false }
        do {
            if playback.isPlaying {
                try await playbackService.pause()
            } else {
                try await playbackService.play()
            }
            try await refreshPlaybackState(forceLyricsReload: false)
            errorMessage = nil
        } catch {
            errorMessage = "No pudimos cambiar el estado de reproduccion."
        }
    }

    func skipToNext() async {
        await performPlaybackCommand {
            try await playbackService.skipToNext()
        }
    }

    func skipToPrevious() async {
        await performPlaybackCommand {
            try await playbackService.skipToPrevious()
        }
    }
}

private extension NowPlayingViewModel {
    func performPlaybackCommand(_ command: () async throws -> Void) async {
        isPerformingPlaybackAction = true
        defer { isPerformingPlaybackAction = false }
        do {
            try await command()
            try await Task.sleep(nanoseconds: 350_000_000)
            try await refreshPlaybackState(forceLyricsReload: false)
            errorMessage = nil
        } catch {
            errorMessage = "No pudimos controlar la reproduccion."
        }
    }

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

    func startPlaybackRefreshTicker() {
        stopPlaybackRefreshTicker()
        playbackRefreshCancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    await self?.refreshLoopTick()
                }
            }
    }

    func refreshLoopTick() async {
        do {
            try await refreshPlaybackState(forceLyricsReload: false)
        } catch {
            // Keep existing UI state; intermittent Spotify connectivity is common.
            #if DEBUG
            print("[NowPlayingViewModel] refreshPlaybackState failed: \(error)")
            #endif
        }
    }

    func refreshPlaybackState(forceLyricsReload: Bool) async throws {
        let latestPlayback = try await playbackService.fetchNowPlaying()
        let previousTrackID = playback?.track.id

        playback = latestPlayback
        currentProgressMS = latestPlayback.progressMS
        updateActiveLyricLine()

        let didTrackChange = previousTrackID != latestPlayback.track.id
        if forceLyricsReload || didTrackChange || lyrics == nil {
            await loadLyrics(for: latestPlayback.track)
        } else {
            publishCarPlaySnapshot()
        }
    }

    func loadLyrics(for track: Track) async {
        do {
            let fetchedLyrics = try await lyricsService.fetchLyrics(for: track)
            lyrics = fetchedLyrics
            updateActiveLyricLine()
            publishCarPlaySnapshot()
        } catch {
            lyrics = LyricsPayload(
                isSynced: false,
                lines: [LyricsLine(timestampMS: nil, text: "No encontramos letras para esta canción.")]
            )
            activeLyricLineID = nil
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
