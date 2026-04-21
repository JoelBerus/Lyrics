import Foundation
import Combine

#if canImport(CarPlay) && os(iOS)
import CarPlay

@MainActor
final class CarPlayCoordinator {
    private weak var interfaceController: CPInterfaceController?
    private var stateCancellable: AnyCancellable?
    private var preferencesCancellable: AnyCancellable?
    private var rootTemplate: CPListTemplate?

    func connect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        bindNowPlayingState()
        renderRootTemplate(snapshot: NowPlayingSharedState.shared.carPlaySnapshot)
    }

    func disconnect() {
        stateCancellable?.cancel()
        stateCancellable = nil
        preferencesCancellable?.cancel()
        preferencesCancellable = nil
        interfaceController = nil
        rootTemplate = nil
    }

    private func bindNowPlayingState() {
        stateCancellable = NowPlayingSharedState.shared.$carPlaySnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.renderRootTemplate(snapshot: snapshot)
            }

        preferencesCancellable = CarPlayPreferencesStore.shared.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderRootTemplate(snapshot: NowPlayingSharedState.shared.carPlaySnapshot)
            }
    }

    private func renderRootTemplate(snapshot: CarPlayLyricsSnapshot?) {
        let preferences = CarPlayPreferencesStore.shared.preferences
        let nowPlayingItem = CPListItem(text: "Now Playing", detailText: "Abrir controles del sistema")
        nowPlayingItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            completion()
        }

        let statusItem = CPListItem(
            text: snapshot?.isPlaying == true ? "Reproduciendo" : "Pausado",
            detailText: snapshot.map { "\($0.trackTitle) - \($0.artist)" } ?? "Conecta Spotify para empezar"
        )

        let currentLineItem = CPListItem(
            text: "Linea actual",
            detailText: snapshot?.currentLine ?? "Sin letra activa"
        )

        var items: [CPListItem] = [nowPlayingItem, statusItem, currentLineItem]

        if !preferences.showOnlyCurrentLine {
            let nextLineItem = CPListItem(
                text: "Siguiente",
                detailText: snapshot?.nextLine ?? "-"
            )
            items.append(nextLineItem)
        }

        let section = CPListSection(
            items: items,
            header: "Lyrics Car Companion",
            sectionIndexTitle: nil
        )
        if let rootTemplate {
            rootTemplate.updateSections([section])
        } else {
            let listTemplate = CPListTemplate(title: "Inicio", sections: [section])
            rootTemplate = listTemplate
            interfaceController?.setRootTemplate(listTemplate, animated: true, completion: nil)
        }
    }
}
#endif
