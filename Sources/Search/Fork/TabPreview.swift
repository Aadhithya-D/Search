import AppKit
import SwiftUI
import WebKit

// Fork: a tab's preview, as Arc and Dia show one. Rest the pointer on a tab
// in the column — a row or a pinned square — and a card comes out beside the
// column: a picture of the page, its title and site, and how much memory its
// page is using. Moving to the next tab while one is up changes it at once;
// leaving the tabs, clicking, or typing puts it away.
//
// The picture is drawn by the page's own process, so a tab off screen can
// still be pictured (Tab.snapshot); a sleeping tab shows the picture it went
// to sleep with. The memory is that process's footprint, the figure Activity
// Monitor shows — one page to a process, as WebKit keeps them.

@MainActor
enum TabPreview {
    private static var panel: NSPanel?
    private static var host: NSHostingView<AnyView>?
    private static var showing: Tab.ID?
    private static var coming: DispatchWorkItem?
    private static var going: DispatchWorkItem?
    /// Pictures already taken, so going back and forth along the tabs
    /// doesn't ask each page to draw again every time.
    private static var pictures: [Tab.ID: (image: NSImage, at: Date)] = [:]

    /// How long the pointer rests before the first card; after that, cards
    /// follow the pointer without waiting.
    private static let dwell: TimeInterval = 0.55
    private static let width: CGFloat = 300

    /// The pointer came onto a tab, or left one.
    static func hover(_ tab: Tab, over: Bool, in browser: Browser) {
        if over {
            going?.cancel()
            going = nil
            guard tab.id != browser.activeID, !tab.isBlank, browser.editingTab == nil, !browser.editing else {
                return hide()
            }
            coming?.cancel()
            if panel != nil {
                show(tab, in: browser)
                return
            }
            let item = DispatchWorkItem { show(tab, in: browser) }
            coming = item
            DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: item)
        } else {
            coming?.cancel()
            coming = nil
            guard showing == tab.id else { return }
            let item = DispatchWorkItem { hide() }
            going = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }
    }

    static func hide() {
        coming?.cancel()
        coming = nil
        going?.cancel()
        going = nil
        showing = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        host = nil
    }

    private static func show(_ tab: Tab, in browser: Browser) {
        guard let window = Links.window, window.isKeyWindow else { return }
        showing = tab.id
        let model = PreviewModel(tab: tab)
        // A sleeping tab has no page to picture: its name and that it sleeps.
        let awake = !tab.asleep && tab.built != nil
        if awake {
            if let kept = pictures[tab.id], Date().timeIntervalSince(kept.at) < 20 {
                model.image = kept.image
            }
            tab.snapshot { data in
                guard showing == tab.id, let data, let image = NSImage(data: data) else { return }
                pictures[tab.id] = (image, Date())
                let first = model.image == nil
                model.image = image
                if first, let window = Links.window { place(in: window, browser: browser) }
            }
        }
        model.memory = TabPreview.memory(of: tab)

        let card = AnyView(PreviewCard(model: model).environment(\.colorScheme, window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light))
        if let host {
            host.rootView = card
        } else {
            let made = NSHostingView(rootView: card)
            host = made
            let glass = NSVisualEffectView()
            glass.material = .menu
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 12
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.layer?.borderWidth = 0.5
            glass.layer?.borderColor = MenuMetrics.edge.cgColor
            glass.addSubview(made)
            let sheet = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            sheet.contentView = glass
            sheet.isOpaque = false
            sheet.backgroundColor = .clear
            sheet.hasShadow = true
            sheet.ignoresMouseEvents = true
            sheet.hidesOnDeactivate = true
            window.addChildWindow(sheet, ordered: .above)
            panel = sheet
        }
        place(in: window, browser: browser)
    }

    /// Beside the column, level with the pointer, kept on the screen.
    private static func place(in window: NSWindow, browser: Browser) {
        guard let panel, let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: host.fittingSize.height)
        let prefs = browser.prefs
        let inset: CGFloat = browser.folded ? Fold.inset : 0
        let x = prefs.sideRight
            ? window.frame.maxX - prefs.sideWidth - inset - 10 - size.width
            : window.frame.minX + prefs.sideWidth + inset + 10
        var y = NSEvent.mouseLocation.y - 24 - size.height + 40
        if let screen = window.screen?.visibleFrame {
            y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        }
        // The panel first, then what is in it, each to the same size: left to
        // autoresize from a card of another size, the new one landed off
        // the panel's corner and the card was drawn half out of its frame.
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        host.frame = NSRect(origin: .zero, size: size)
        panel.display()
    }

    // MARK: - memory

    /// The page's process's footprint, in bytes; nil for a page that has none.
    static func memory(of tab: Tab) -> UInt64? {
        guard let web = tab.built else { return nil }
        let get = NSSelectorFromString("_webProcessIdentifier")
        guard web.responds(to: get) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> pid_t
        let pid = unsafeBitCast(web.method(for: get), to: Getter.self)(web, get)
        guard pid > 0 else { return nil }
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }
}

@MainActor
private final class PreviewModel: ObservableObject {
    let tab: Tab
    @Published var image: NSImage?
    @Published var memory: UInt64?
    init(tab: Tab) { self.tab = tab }
}

private struct PreviewCard: View {
    @ObservedObject var model: PreviewModel

    private var site: String {
        guard let url = model.tab.address else { return "" }
        return SiteCard.site(url)
    }

    private var memoryLine: String {
        if model.tab.asleep || model.tab.built == nil { return "Asleep · not using memory" }
        guard let bytes = model.memory else { return "Memory usage unknown" }
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 { return String(format: "Memory usage: %.1f GB", megabytes / 1024) }
        return "Memory usage: \(Int(megabytes.rounded())) MB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 300, height: 170, alignment: .top)
                    .clipped()
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.tab.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if !site.isEmpty {
                    Text(site)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Image(systemName: model.tab.asleep || model.tab.built == nil ? "moon.zzz" : "memorychip")
                        .font(.system(size: 10.5))
                    Text(memoryLine)
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .foregroundStyle(Palette.muted)
                .padding(.top, 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300)
        .popGround()
        .fixedSize(horizontal: false, vertical: true)
    }
}
