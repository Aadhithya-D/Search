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
        let immersed = state != .notInFullscreen
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
