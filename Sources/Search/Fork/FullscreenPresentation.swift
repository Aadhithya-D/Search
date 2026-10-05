import AppKit
import WebKit

/// WebKit lends the page to its fullscreen window. Keep the browser's
/// chrome tied to that native lifecycle, rather than an optimistic JS flag.
@MainActor
final class FullscreenPresentation {
    private weak var tab: Tab?
    private weak var web: WKWebView?
    private weak var origin: NSWindow?
    private var observation: NSKeyValueObservation?

    func watch(_ web: WKWebView, tab: Tab) {
        stop()
        self.tab = tab
        self.web = web
        observation = web.observe(\.fullscreenState, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    func reconcile() {
        guard let web, let tab else { return }
        let state = web.fullscreenState
        // The window steps aside only while the video has the screen, when
        // it is out of sight in a Space of its own. Stepping aside as WebKit
        // began, the window went black and lost its column under the video's
        // zoom out of the page; and kept so until WebKit had finished going
        // back, it was black for the second macOS takes to slide the Space
        // away, then the column came. Now the page grows out of the window
        // as it was, and goes back into it whole.
        let immersed = state == .inFullscreen
        if tab.immersed != immersed { tab.immersed = immersed }
        switch state {
        case .enteringFullscreen:
            if origin == nil {
                origin = Browsers.all.first(where: { $0.tabs.contains(where: { $0 === tab }) })?.window ?? web.window
            }
        case .notInFullscreen:
            restore()
        case .inFullscreen, .exitingFullscreen:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        observation = nil
        if tab?.immersed == true { tab?.immersed = false }
        restore()
        web = nil
        tab = nil
    }

    private func restore() {
        guard let origin else { return }
        self.origin = nil
        // WebKit can put an old tab back after the stage has selected a new
        // one. Reconcile every stage once the native reparenting completes.
        DispatchQueue.main.async { [weak origin] in
            func refresh(_ view: NSView) {
                if view is StageView { view.needsLayout = true }
                view.subviews.forEach(refresh)
            }
            if let content = origin?.contentView {
                refresh(content)
                content.layoutSubtreeIfNeeded()
            }
        }
    }

    static func selected(in browser: Browser) {
        browser.active?.fullscreen.reconcile()
    }
}
