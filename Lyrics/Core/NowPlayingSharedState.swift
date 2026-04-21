import Foundation
import Combine

struct CarPlayLyricsSnapshot: Equatable {
    let trackTitle: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
}

@MainActor
final class NowPlayingSharedState: ObservableObject {
    static let shared = NowPlayingSharedState()

    @Published private(set) var carPlaySnapshot: CarPlayLyricsSnapshot?

    private init() {}

    func update(snapshot: CarPlayLyricsSnapshot?) {
        carPlaySnapshot = snapshot
    }
}
