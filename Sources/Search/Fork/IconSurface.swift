import AppKit
import Combine

// Fork: a site's icon for a dark scheme is chosen by the surface it is drawn
// on, not by the window. A space can wear its pastel on a dark window
// (Space.tone), and there the dark variant — often a white glyph, as
// chatgpt.com's is — was drawn white on a light column, and looked missing.

extension Favicons {
    /// Whether the column the icons sit in is dark; nil where the tabs are
    /// across the top, on the window's own ground.
    @MainActor static var surfaceDark: Bool?
}

@MainActor
private var iconSurfaceBag = Set<AnyCancellable>()

extension Browser {
    /// Keeps `Favicons.surfaceDark` on the column's tone, and looks the
    /// icons up again when it turns over.
    func followIconSurface() {
        let settle = { [weak self] in
            guard let self else { return }
            let windowDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let wanted: Bool? = self.prefs.sidebar ? self.space.wearsDark(on: windowDark) : nil
            guard wanted != Favicons.surfaceDark else { return }
            Favicons.surfaceDark = wanted
            self.relook()
        }
        // A beat after each change, so the published values and the
        // window's appearance have both turned over.
        let later = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { settle() } } }
        $spaceID.sink { _ in later() }.store(in: &iconSurfaceBag)
        $spaces.sink { _ in later() }.store(in: &iconSurfaceBag)
        prefs.$sidebar.sink { _ in later() }.store(in: &iconSurfaceBag)
        prefs.$look.sink { _ in later() }.store(in: &iconSurfaceBag)
        DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: DispatchQueue.main)
            .sink { _ in later() }
            .store(in: &iconSurfaceBag)
    }
}
