import Foundation

struct LyricsLine: Identifiable, Codable, Equatable {
    let timestampMS: Int?
    let text: String

    var id: String {
        "\(timestampMS ?? -1)-\(text)"
    }
}

struct LyricsPayload: Codable, Equatable {
    let isSynced: Bool
    let lines: [LyricsLine]
}
