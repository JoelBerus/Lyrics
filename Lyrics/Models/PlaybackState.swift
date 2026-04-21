import Foundation

struct PlaybackState: Codable, Equatable {
    let isPlaying: Bool
    let progressMS: Int
    let track: Track
}
