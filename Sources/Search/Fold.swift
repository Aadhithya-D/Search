import SwiftUI

// The column of tabs, folded away with ⌘S.
//
// The column is two hundred and some points the page never gets back, even
// while all you do is read. Folded, the page takes the whole window. The tabs
// are one push against the column's edge away — the left, or the right if
// the column was moved there: it slides out over the page, the same column
// with the same rows, and goes again once the pointer leaves it. A short
// grace before it goes, so a hand that overshoots on the way back in doesn't
// lose it. A small handle fades in on that same edge as the pointer
// approaches, and a click on it keeps the column out.
//
// The traffic lights live in whichever chrome is holding the window's top-left
// corner: the column, when it is open on the left, and the address bar
// otherwise. Left alone over a page they sit on top of whatever the page put
// in its own corner — a logo, a menu button — so they go with that chrome
// and come back when it does. A column on the right never takes them; the
// window's buttons stay on the left, in the address bar.
//
// Folding lasts the session. A browser opening with no tabs anywhere on
// screen, for a reason set days ago, reads as a broken one.
//
// Unless that is the reason: Settings can keep the column folded for good,
// Arc's way, and then the fold is where it rests, at launch and after every
// change of layout. ⌘S still brings it out to stay, and puts it away again.
// Folded like that, the edge is met far more often by a hand on its way
// somewhere else — the Dock, the window beside — than by one reaching for
// the tabs, so the column waits for the pointer to settle there a moment
// before it comes. Folded by hand with ⌘S, it comes at once, as it always did.
//
// While a tab's address is being typed into its row, the column stays out:
// the pointer drifting off it is no reason to take the field away.
//
// The strip across the top folds the same way: up out of the window, the
// page taking the full height, and back down over the page when the pointer
// rests against the top edge. There the edge is crossed on every trip to the
// menu bar just above, so the strip always waits for the pointer to settle.

extension Browser {
    /// ⌘S. The column, or the strip across the top, out of the way, or back.
    func toggleFold() {
        peeking = false
        withAnimation(Motion.glide) { folded.toggle() }
    }

    /// The folded column out over the page, or back in.
    func peek(_ out: Bool) {
        withAnimation(Motion.glide) { peeking = out }
    }

    /// The hidden address bar down over the page, or back up.
    func peekBar(_ out: Bool) {
        guard barPeeking != out else { return }
        withAnimation(Motion.glide) { barPeeking = out }
    }
}

/// Over the window while the column or the strip is folded: the column or
/// the strip itself while it is out, brought out by the pointer at the
/// window's left edge, or its top edge.
struct Fold: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    /// The column going back in, a moment after the pointer left it.
    @State private var leaving: DispatchWorkItem?
    /// The column coming out, once the pointer has settled on the edge.
    @State private var arriving: DispatchWorkItem?
    /// The pointer is over the column.
    @State private var inside = false
    /// The address bar, on its own clock: it can be out while the column is
    /// in, and the other way around.
    @State private var barLeaving: DispatchWorkItem?
    @State private var barArriving: DispatchWorkItem?
    @State private var barInside = false
    /// The pointer is close enough to the column's edge for its handle.
    @State private var edgeNear = false
    @State private var pointer = Pointer()

    /// How near the edge the pointer has to be.
    private static let edge: CGFloat = 6
    /// How near the column's edge its handle fades in.
    private static let approach: CGFloat = 56
    /// The grace before the column goes back in.
    private static let grace: TimeInterval = 0.3
    /// The band along the top that is the title bar over the page.
    private static let top: CGFloat = 8
    /// How long the pointer rests on the edge before a column folded for
    /// good comes out. Long enough to cross the edge, short enough not to be
    /// waited for.
    private static let dwell: TimeInterval = 0.15

    var body: some View {
        ZStack(alignment: .topLeading) {
            // In the column's mode the page reaches the window's top edge —
            // beside the column, and everywhere once it is folded away — and
            // there was nowhere there to drag the window from, or to
            // double-click to fill the screen: only the column's own corner,
            // gone when folded. A band too thin to be in a page's way stands
            // in for the title bar along the whole top; the column lies over
            // it with its own.
            if prefs.sidebar, browser.active?.immersed != true, browser.prefs.barHides, !barOverlay {
                DragStrip()
                    .frame(height: Fold.top)
                    .frame(maxWidth: .infinity)
            }
            if barOverlay {
                URLBar(browser: browser, showsLights: reserveLights, showsChrome: prefs.sidebar)
                    .padding(.leading, docked && !prefs.sideRight ? prefs.sideWidth : 0)
                    .padding(.trailing, docked && prefs.sideRight ? prefs.sideWidth : 0)
                    .padding(.top, barTop)
                    .transition(.move(edge: .top))
            }
            if folding, !prefs.sidebar, browser.peeking {
                // The row has no ground of its own: in the window it lies on
                // the window's. Out over the page it brings that ground along,
                // as the column does, or the page showed through between the
                // tabs, and the shadow fell from every title and icon rather
                // than from the row's edge.
                TabBar(browser: browser)
                    .background {
                        Palette.ground
                            .shadow(color: .black.opacity(0.14), radius: 20, y: 4)
                    }
                    .transition(.move(edge: .top))
            }
            ZStack(alignment: prefs.sideRight ? .trailing : .leading) {
                Color.clear.frame(width: 0)
                if folding, prefs.sidebar, browser.peeking {
                    SideBar(browser: browser, prefs: prefs, bookmarks: browser.bookmarks)
                        .shadow(color: .black.opacity(0.14), radius: 20, x: prefs.sideRight ? -4 : 4)
                        .transition(.move(edge: prefs.sideRight ? .trailing : .leading))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: prefs.sideRight ? .trailing : .leading) {
            if prefs.sidebar, folding, !browser.peeking {
                SideHandle(right: prefs.sideRight, near: edgeNear) {
                    pass()
                    withAnimation(Motion.glide) {
                        browser.peeking = false
                        browser.folded = false
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            hideLights()
            watch()
        }
        .onDisappear { pointer.stop() }
        // A column folded for good is folded before there is a window to
        // hide the lights of; they go once there is one.
        .background(WindowSetup { window in
            window.standardWindowButton(.closeButton)?.superview?.isHidden = lightsOff
            pointer.window = window
            watch()
        })
        .onChange(of: lightsOff) { _, _ in hideLights() }
        .onChange(of: watching) { _, _ in watch() }
        // Back to the strip and then to the column again: the column comes
        // back as it rests — whole, not folded from a time nobody remembers,
        // unless Settings says it rests folded.
        .onChange(of: prefs.sidebar) { _, _ in
            browser.folded = prefs.sidebar && prefs.sideHides
            browser.peeking = false
        }
        .onChange(of: prefs.sideHides) { _, hides in
            guard prefs.sidebar else { return }
            browser.peeking = false
            withAnimation(Motion.glide) { browser.folded = hides }
        }
        .onChange(of: prefs.barHides) { _, hides in
            if !hides {
                passBar()
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { browser.barPeeking = false }
            }
            watch()
        }
        // The address typed into a row is done with, and the pointer went
        // elsewhere while it was: the column goes the way it would have.
        .onChange(of: browser.editingTab) { _, editing in
            if editing == nil, !inside, browser.peeking { peek(false) }
        }
        // Typing an address keeps the bar down over the page. A blank tab's
        // field is the one in the middle, so that one doesn't pull the bar out.
        .onChange(of: browser.editing) { _, editing in
            guard prefs.barHides, browser.active?.immersed != true else { return }
            if editing, browser.active?.isBlank != true {
                passBar()
                browser.peekBar(true)
            } else if !barInside, browser.barPeeking {
                peekBar(false)
            }
        }
    }

    /// Folded, and not taken over by a page filling the screen.
    private var folding: Bool {
        browser.folded && browser.active?.immersed != true
    }

    /// The column, the strip, or the address bar has something for the
    /// pointer to bring out.
    private var watching: Bool {
        folding || (prefs.barHides && browser.active?.immersed != true)
    }

    /// The column is in the layout, not slid out over the page.
    private var docked: Bool {
        prefs.sidebar && !browser.folded && browser.active?.immersed != true
    }

    /// The address bar drawn over the page. Typing into a loaded page keeps
    /// it there; a blank tab's field is the one in the middle.
    private var barOverlay: Bool {
        guard prefs.barHides, browser.active?.immersed != true else { return false }
        let typing = browser.editing && browser.active?.isBlank != true
        return browser.barPeeking || typing
    }

    /// The bar includes the window's left edge, so the traffic lights have a
    /// row in it. A column docked on the left already holds them.
    private var reserveLights: Bool {
        prefs.sidebar && !(docked && !prefs.sideRight)
    }

    /// Under the tab strip when that strip is the top row; otherwise the
    /// window's top edge.
    private var barTop: CGFloat {
        guard !prefs.sidebar else { return 0 }
        if !browser.folded || browser.peeking { return Metrics.strip }
        return 0
    }

    /// Hidden when nothing at the window's top-left is showing them. The
    /// column holds them only on the left; a column on the right leaves them
    /// to the address bar.
    private var lightsOff: Bool {
        if !prefs.sidebar {
            return browser.folded && !browser.peeking
        }
        let leftHolding = !prefs.sideRight && (!browser.folded || browser.peeking)
        let typing = browser.editing && browser.active?.isBlank != true
        let barHolding = !prefs.barHides || browser.barPeeking || typing
        return !leftHolding && !barHolding
    }

    /// The pointer is watched only while there is something folded for it
    /// to bring out; the rest of the time no move of it costs anything.
    private func watch() {
        if watching {
            pointer.start { follow() }
        } else {
            pointer.stop()
            if edgeNear { edgeNear = false }
        }
    }

    /// Opens or closes the column and the address bar from the pointer's
    /// actual position, on every move. Hover events weren't enough: a view
    /// that appears under a still pointer never gets "entered", so it never
    /// gets "exited" either, and after a few quick opens and closes the
    /// column stayed open, or the edge stopped opening it.
    private func follow() {
        guard let window = pointer.window, window.isVisible else {
            pass()
            passBar()
            return
        }
        let screen = NSEvent.mouseLocation
        let point = window.convertPoint(fromScreen: screen)
        let size = window.frame.size
        let inWindow = point.x >= 0 && point.x < size.width && point.y >= 0 && point.y < size.height
        let top = NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0)
        let onWindow = top == window.windowNumber
        let onOwnPanel = !onWindow && NSApp.windows.contains { $0.windowNumber == top }

        if folding {
            if prefs.sidebar {
                let distance = prefs.sideRight ? size.width - point.x : point.x
                let near = onWindow && inWindow && distance >= 0 && distance < Fold.approach
                if near != edgeNear { edgeNear = near }
                followSide(distance: distance, inWindow: inWindow, onWindow: onWindow, onOwnPanel: onOwnPanel)
            } else {
                if edgeNear { edgeNear = false }
                followStrip(distance: size.height - point.y, inWindow: inWindow, onWindow: onWindow, onOwnPanel: onOwnPanel)
            }
        } else if edgeNear {
            edgeNear = false
        }

        if prefs.barHides, browser.active?.immersed != true {
            followBar(distance: size.height - point.y, inWindow: inWindow, onWindow: onWindow, onOwnPanel: onOwnPanel)
        }
    }

    /// The column, from its own edge.
    private func followSide(distance: CGFloat, inWindow: Bool, onWindow: Bool, onOwnPanel: Bool) {
        if browser.peeking {
            pass()
            let over = onOwnPanel || (onWindow && inWindow && distance >= 0 && distance < prefs.sideWidth)
            if over != inside { inside = over }
            peek(over)
        } else if inWindow, onWindow, distance >= 0, distance < Fold.edge {
            if arriving == nil { arrive() }
        } else {
            pass()
        }
    }

    /// The strip, from the top edge. Its edge is the way to the menu bar, so
    /// it always waits for the pointer to settle.
    private func followStrip(distance: CGFloat, inWindow: Bool, onWindow: Bool, onOwnPanel: Bool) {
        if browser.peeking {
            pass()
            let over = onOwnPanel || (onWindow && inWindow && distance >= 0 && distance < Metrics.strip)
            if over != inside { inside = over }
            peek(over)
        } else if inWindow, onWindow, distance >= 0, distance < Fold.edge {
            if arriving == nil { arrive() }
        } else {
            pass()
        }
    }

    /// The address bar, from the top. While the tab strip is the top row, the
    /// band just under it is the edge — the strip itself is for the tabs.
    private func followBar(distance: CGFloat, inWindow: Bool, onWindow: Bool, onOwnPanel: Bool) {
        let typing = browser.editing && browser.active?.isBlank != true
        if typing {
            passBar()
            if !barInside { barInside = true }
            browser.peekBar(true)
            return
        }
        let underStrip = !prefs.sidebar && !browser.folded
        let edge = underStrip ? Metrics.strip + Fold.top : Fold.top
        let reach = underStrip ? Metrics.strip + URLBar.height + 4 : URLBar.height + 4
        let inBand = underStrip
            ? (distance >= Metrics.strip && distance < edge)
            : (distance >= 0 && distance < edge)
        if browser.barPeeking {
            passBar()
            let overBand = underStrip
                ? (distance >= Metrics.strip && distance < reach)
                : (distance >= 0 && distance < reach)
            let over = onOwnPanel || (onWindow && inWindow && overBand)
            if over != barInside { barInside = over }
            peekBar(over)
        } else if inWindow, onWindow, inBand {
            if barArriving == nil { arriveBar() }
        } else {
            passBar()
        }
    }

    /// The pointer on the edge: out at once, or after the dwell when the
    /// column is folded for good, and always for the strip, whose edge is
    /// the way to the menu bar.
    private func arrive() {
        guard !prefs.sidebar || prefs.sideHides else { return peek(true) }
        pass()
        let coming = DispatchWorkItem {
            arriving = nil
            peek(true)
        }
        arriving = coming
        DispatchQueue.main.asyncAfter(deadline: .now() + Fold.dwell, execute: coming)
    }

    /// The pointer crossed the edge without stopping.
    private func pass() {
        guard let arriving else { return }
        arriving.cancel()
        self.arriving = nil
    }

    /// Out at once; in only once the pointer has stayed away for the grace,
    /// counted from when it left rather than from its latest move.
    private func peek(_ out: Bool) {
        if out {
            if let leaving {
                leaving.cancel()
                self.leaving = nil
            }
            guard !browser.peeking else { return }
            browser.peek(true)
        } else {
            guard leaving == nil else { return }
            let going = DispatchWorkItem {
                leaving = nil
                guard browser.editingTab == nil else { return }
                browser.peek(false)
            }
            leaving = going
            DispatchQueue.main.asyncAfter(deadline: .now() + Fold.grace, execute: going)
        }
    }

    /// The pointer on the top edge: the bar waits out a trip to the menu.
    private func arriveBar() {
        passBar()
        let coming = DispatchWorkItem {
            barArriving = nil
            peekBar(true)
        }
        barArriving = coming
        DispatchQueue.main.asyncAfter(deadline: .now() + Fold.dwell, execute: coming)
    }

    private func passBar() {
        guard let barArriving else { return }
        barArriving.cancel()
        self.barArriving = nil
    }

    private func peekBar(_ out: Bool) {
        if out {
            if let barLeaving {
                barLeaving.cancel()
                self.barLeaving = nil
            }
            guard !browser.barPeeking else { return }
            browser.peekBar(true)
        } else {
            guard barLeaving == nil else { return }
            let going = DispatchWorkItem {
                barLeaving = nil
                let typing = browser.editing && browser.active?.isBlank != true
                guard !typing else { return }
                browser.peekBar(false)
            }
            barLeaving = going
            DispatchQueue.main.asyncAfter(deadline: .now() + Fold.grace, execute: going)
        }
    }

    /// The title bar's own view holds the three buttons and the resting
    /// circles drawn over them while the app is behind (see RestingLights),
    /// so hiding it hides both, and hidden buttons take no clicks. In the
    /// column's layout they leave off the top with the address bar; the
    /// column on the left keeps them by simply not sending them away.
    private func hideLights() {
        guard let bar = Fold.titlebar else { return }
        if prefs.sidebar {
            Fold.slide(bar, off: lightsOff, by: URLBar.height, up: true)
        } else {
            Fold.slide(bar, off: lightsOff, by: Metrics.strip, up: true)
        }
    }

    static var titlebar: NSView? {
        Links.window?.standardWindowButton(.closeButton)?.superview
    }

    /// Bumped by every slide, so one that was overtaken doesn't hide the
    /// lights on its way out.
    private static var slides = 0

    /// The lights ride with the column, as everything else in its corner
    /// does. Shown or hidden at once, they stood in their place while the
    /// column was still sliding in under them, and vanished before it had
    /// gone. So they come in from the left edge and go back off it, on the
    /// column's own spring (Motion.glide, in Core Animation's terms) — from
    /// wherever they are, when the pointer turns back halfway. `up`: off the
    /// top edge with the strip rather than off the left edge with the column.
    static func slide(_ bar: NSView, off: Bool, by width: CGFloat, up: Bool = false) {
        slides += 1
        let turn = slides
        guard let layer = bar.layer else {
            bar.isHidden = off
            return
        }
        // Up is +y in a superview that isn't flipped, -y in one that is.
        let path = up ? "transform.translation.y" : "transform.translation.x"
        let gone: CGFloat = up ? ((bar.superview?.isFlipped ?? false) ? -width : width) : -width
        let other = up ? "transform.translation.x" : "transform.translation.y"
        let moving = layer.animation(forKey: "fold") != nil
        // A slide still running on the other axis — the layout was switched
        // halfway — is simply let go.
        if moving, (layer.animation(forKey: "fold") as? CABasicAnimation)?.keyPath == other {
            layer.removeAnimation(forKey: "fold")
        }
        let still = layer.animation(forKey: "fold") != nil
        let from = still
            ? (layer.presentation()?.value(forKeyPath: path) as? CGFloat ?? 0)
            : (bar.isHidden ? gone : 0)
        let to: CGFloat = off ? gone : 0
        guard from != to else {
            layer.removeAnimation(forKey: "fold")
            bar.isHidden = off
            return
        }
        let spring = CASpringAnimation(keyPath: path)
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / 0.34, 2)
        spring.damping = 4 * .pi * 0.82 / 0.34
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false
        bar.isHidden = false
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                guard turn == slides else { return }
                layer.removeAnimation(forKey: "fold")
                bar.isHidden = off
            }
        }
        layer.add(spring, forKey: "fold")
        CATransaction.commit()
    }
}

/// The handle on the column's edge. It fades in as the pointer approaches
/// and a click keeps the column out, on whichever side the column is set to.
private struct SideHandle: View {
    let right: Bool
    let near: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: right ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 22, height: 28)
                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(right ? .trailing : .leading, 6)
        .help("Show Sidebar")
        .opacity(near ? 1 : 0)
        .allowsHitTesting(near)
        .animation(Motion.quick, value: near)
    }
}

/// The pointer's moves, wherever it goes, while something is folded: over
/// this app's windows, and over everything else while another app is in
/// front, since the edge is still the edge with Search behind.
@MainActor
private final class Pointer {
    weak var window: NSWindow?
    private var local: Any?
    private var global: Any?
    /// The window's own say on mouse-moved events, given back when the
    /// watch ends.
    private var accepted = false

    func start(_ moved: @escaping @MainActor () -> Void) {
        guard local == nil, let window else { return }
        // The pointer's moves reach the monitor wherever it is over the
        // window, not only over what tracks it — for as long as the watch
        // lasts, and no longer.
        accepted = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            MainActor.assumeIsolated { moved() }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            MainActor.assumeIsolated { moved() }
        }
    }

    func stop() {
        guard local != nil || global != nil else { return }
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
        window?.acceptsMouseMovedEvents = accepted
    }
}
