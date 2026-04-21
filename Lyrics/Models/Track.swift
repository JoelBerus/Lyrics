import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let durationMS: Int
}
