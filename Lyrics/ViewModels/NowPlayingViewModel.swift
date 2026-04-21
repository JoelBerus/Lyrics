import Foundation
import Combine

@MainActor
final class NowPlayingViewModel: ObservableObject {
    enum LyricsAlignment: String, CaseIterable {
        case left
        case center
    }

    @Published var playback: PlaybackState?
    @Published var lyrics: LyricsPayload?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentProgressMS: Int = 0
    @Published var activeLyricLineID: String?
    @Published var isPerformingPlaybackAction = false
    @Published var isLyricsBlurEnabled = true
    @Published var lyricsAlignment: LyricsAlignment = .left
    @Published var isTrackLiked = false
    @Published var isTrackLikeLoading = false
    @Published var isTranslationEnabled = false

    private let playbackService: SpotifyPlaybackServiceProtocol
    private let lyricsService: LyricsServiceProtocol
    private var progressCancellable: AnyCancellable?
    private var playbackRefreshCancellable: AnyCancellable?
    private var likedTrackID: String?

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
            errorMessage = playbackActionErrorMessage(error)
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

    func toggleLike() async {
        guard let trackID = playback?.track.id else { return }
        guard !isTrackLikeLoading else { return }

        isTrackLikeLoading = true
        defer { isTrackLikeLoading = false }

        let shouldSave = !isTrackLiked
        do {
            if shouldSave {
                try await playbackService.saveTrack(trackID: trackID)
            } else {
                try await playbackService.removeTrack(trackID: trackID)
            }
            isTrackLiked = shouldSave
            likedTrackID = trackID
        } catch {
            errorMessage = "No pudimos actualizar Me gusta."
        }
    }

    func setLyricsAlignment(_ alignment: LyricsAlignment) {
        lyricsAlignment = alignment
    }

    func toggleLyricsBlur() {
        isLyricsBlurEnabled.toggle()
    }

    func toggleTranslation() {
        isTranslationEnabled.toggle()
    }

    func seekToLyricLine(_ line: LyricsLine) async {
        guard let targetTimestamp = line.timestampMS else { return }
        guard playback != nil else { return }

        isPerformingPlaybackAction = true
        defer { isPerformingPlaybackAction = false }

        do {
            try await playbackService.seek(to: targetTimestamp)
            try await Task.sleep(nanoseconds: 250_000_000)
            try await refreshPlaybackState(forceLyricsReload: false)
            errorMessage = nil
        } catch {
            errorMessage = playbackActionErrorMessage(error)
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
            errorMessage = playbackActionErrorMessage(error)
        }
    }

    func playbackActionErrorMessage(_ error: Error) -> String {
        guard let playbackError = error as? SpotifyPlaybackError else {
            return "No pudimos controlar la reproduccion."
        }
        switch playbackError {
        case .commandRejected(let statusCode) where statusCode == 401:
            return "Faltan permisos de control. Desconecta y reconecta Spotify."
        case .commandRejected(let statusCode) where statusCode == 403:
            return "Spotify rechazo el control. Reconecta para actualizar permisos."
        case .commandRejected(let statusCode) where statusCode == 404:
            return "No hay dispositivo activo en Spotify para controlar."
        case .commandRejected(let statusCode):
            return "Spotify devolvio error \(statusCode) al controlar."
        default:
            return "No pudimos controlar la reproduccion."
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

        if likedTrackID != latestPlayback.track.id {
            await refreshLikedState(for: latestPlayback.track.id)
        }

        let didTrackChange = previousTrackID != latestPlayback.track.id
        if forceLyricsReload || didTrackChange || lyrics == nil {
            await loadLyrics(for: latestPlayback.track)
        } else {
            publishCarPlaySnapshot()
        }
    }

    func refreshLikedState(for trackID: String) async {
        do {
            let liked = try await playbackService.isTrackSaved(trackID: trackID)
            isTrackLiked = liked
            likedTrackID = trackID
        } catch {
            isTrackLiked = false
            likedTrackID = trackID
        }
    }

    func loadLyrics(for track: Track) async {
        do {
            let fetchedLyrics = try await lyricsService.fetchLyrics(for: track)
            lyrics = fetchedLyrics
            updateActiveLyricLine()
            publishCarPlaySnapshot()
        } catch {
            #if DEBUG
            print("[NowPlayingViewModel] loadLyrics failed for track='\(track.title)' artist='\(track.artist)' error=\(error)")
            #endif
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
