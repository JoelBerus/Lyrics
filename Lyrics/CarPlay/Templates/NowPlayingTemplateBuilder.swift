import Foundation

#if canImport(CarPlay) && os(iOS)
import CarPlay

enum NowPlayingTemplateBuilder {
    static func build() -> CPNowPlayingTemplate {
        CPNowPlayingTemplate.shared
    }
}
#endif
