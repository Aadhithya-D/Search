import SwiftUI
import AppKit

// Fork: the extensions, inside the site's controls in the column's address,
// for a column too narrow for the puzzle button — where Arc keeps them too.
// A popup whose button isn't on screen hangs from those controls instead.

@available(macOS 15.4, *)
extension Extensions {
    /// Where a popup hangs when the puzzle button isn't on screen either:
    /// the site's controls in the column's address.
    static let siteAnchor = "__site"

    /// The puzzle button, or the site's controls when the column had no
    /// room for the puzzle.
    var fallbackAnchor: NSView? {
        if let menu = anchors[Extensions.menuAnchor]?.view, menu.window != nil { return menu }
        return anchors[Extensions.siteAnchor]?.view
    }
}

/// The extensions' list, where it is not behind the puzzle button: in the
/// site's controls, under Show Reader. `close` puts that away first.
@available(macOS 15.4, *)
struct ExtensionsInline: View {
    let close: () -> Void
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SiteCard.Header(title: "Extensions")
            ForEach(extensions.buttons) { button in
                Line(button: button) {
                    close()
                    let id = button.id
                    // The popover goes first; the popup then hangs from the
                    // site's controls it came out of.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { extensions.press(id) }
                }
                .contextMenu { ExtensionActions(id: button.id, name: button.name, extensions: extensions) }
            }
            // Where more come from, apart from the ones there are.
            SiteCard.Separator()
            SiteCard.Row("Chrome Web Store…") {
                close()
                extensions.browser?.open(Browser.webStore, foreground: true)
            }
            SiteCard.Row("Manage Extensions…") {
                close()
                Store.settings.set("extensions", forKey: "settings.page")
                extensions.browser?.tuning = true
            }
        }
    }

    /// An extension, as a menu line with its icon before the name.
    private struct Line: View {
        let button: Extensions.Button
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 7) {
                ExtensionIcon(button: button, size: 15)
                Text(button.name)
                    .font(MenuMetrics.font)
                    .foregroundStyle(hovering ? Color.white : Color(nsColor: button.enabled ? .labelColor : .secondaryLabelColor))
                    .lineLimit(1)
                Spacer(minLength: 24)
            }
            .padding(.leading, MenuMetrics.text - MenuMetrics.inset)
            .padding(.trailing, MenuMetrics.trailing - MenuMetrics.inset)
            .frame(height: MenuMetrics.row)
            .background(
                RoundedRectangle(cornerRadius: MenuMetrics.highlight, style: .continuous)
                    .fill(hovering ? MenuMetrics.selection : .clear)
            )
            .padding(.horizontal, MenuMetrics.inset)
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
            .help(button.label)
        }
    }
}

/// A view the popups can hang from when there is no puzzle button.
struct ExtensionSiteAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        note(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { note(view) }

    private func note(_ view: NSView) {
        if #available(macOS 15.4, *) {
            Extensions.shared.anchors[Extensions.siteAnchor] = WeakView(view)
        }
    }
}
