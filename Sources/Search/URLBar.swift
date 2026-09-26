import SwiftUI

/// The address, across the top of the page.
///
/// Beside a column of tabs it is the whole top row: the traffic lights when
/// they aren't sitting in the column, then back, forward and reload, the
/// address, and any extension pinned out of the puzzle menu. Under the tab
/// strip it is only the address — those controls already live in the strip.
/// A blank tab keeps a second field in the middle of the page (see Omnibox);
/// this one then shows the same prompt and sends a click there, so the two
/// never both try to take the keyboard.
struct URLBar: View {
    @ObservedObject var browser: Browser
    /// The bar includes the window's left edge, so it leaves the traffic
    /// lights their row.
    var showsLights = false
    /// Back, forward, reload, and the pinned extensions. The tab strip has
    /// its own of each, so this is the column's layout only.
    var showsChrome = false

    /// Shorter than the tab strip, and shorter than the row it replaces.
    static let height: CGFloat = 34
    /// The address itself. Short enough that a modest radius reads as part
    /// of the window rather than a capsule floating in it.
    private static let pill: CGFloat = 22
    private static let radius: CGFloat = 8

    @State private var shake: CGFloat = 0
    @State private var refused = false

    var body: some View {
        HStack(spacing: 6) {
            if showsLights {
                DragStrip()
                    .frame(width: Metrics.lights - 8, height: URLBar.height)
            }
            if showsChrome {
                Helm(browser: browser)
            }
            pill
            if showsChrome {
                ExtensionSlot(edge: .bottom)
            }
        }
        .padding(.horizontal, showsChrome || showsLights ? 8 : 12)
        .frame(maxWidth: .infinity)
        .frame(height: URLBar.height)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var pill: some View {
        HStack(spacing: 8) {
            if let url = browser.active?.address, !typingHere {
                Image(systemName: url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(url.scheme == "https" ? Palette.muted : Palette.unsafe)
            }

            if typingHere {
                AddressField(browser: browser, point: 12.5, prompt: browser.prefs.searchPrompt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
            } else {
                Text(shown)
                    .font(.system(size: 12.5))
                    .foregroundStyle(browser.active?.address == nil ? Palette.ink.opacity(0.38) : Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: URLBar.pill)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: URLBar.radius, style: .continuous)
                .fill(Palette.wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: URLBar.radius, style: .continuous)
                .strokeBorder(refused ? Color.red.opacity(0.35) : Palette.hairline, lineWidth: 1)
        )
        .modifier(Shake(travel: shake))
        .modifier(EditOnTap(armed: browser.active?.isBlank == true) { browser.askFocus() })
        .modifier(EditOnTap(armed: !browser.fieldShowing) { browser.edit() })
        .onChange(of: browser.refusals) { _, _ in
            shake = 0
            refused = true
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
        }
        .onChange(of: browser.typed) { _, _ in
            withAnimation(Motion.quick) { refused = false }
        }
    }

    /// The field is this bar's only while a page is loaded. A blank tab's
    /// field is the one in the middle of the page.
    private var typingHere: Bool {
        browser.fieldShowing && browser.active?.isBlank != true
    }

    /// The address as the bar shows it at rest: the host and the path, and
    /// the query when there is one. Clicking it puts the whole address in
    /// the field, scheme and all. Nothing loaded yet: the same prompt as the
    /// field in the middle.
    private var shown: String {
        guard let url = browser.active?.address else { return browser.prefs.searchPrompt }
        let pretty = Address.pretty(url)
        guard let query = url.query, !query.isEmpty else { return pretty }
        return pretty + "?" + query
    }
}

/// A tap opens the field. Absent while the field is up, so the tap reaches
/// the text field instead of being taken as another request to select all.
private struct EditOnTap: ViewModifier {
    let armed: Bool
    let edit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if armed {
            content
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture(perform: edit)
        } else {
            content
        }
    }
}
