import SwiftUI

// Fork: Clear, at the right of the line above New Tab, as in Arc. The first
// press closes every tab under New Tab but the one on screen; the next
// closes that one too. Pins and bookmarks are not tabs of that list, and
// stay. Each goes the way ⌘W would take it, so it can be reopened, and
// the last one leaves a new tab (Fork/LastTabClosed.swift).
//
// From Adithya Sakaray's PR #1.

extension Browser {
    func clearLoose() {
        let loose = tabs.filter { $0.pin == nil && $0.bookmark == nil }
        guard !loose.isEmpty else { return }
        let staying: Tab.ID? = loose.count > 1 ? loose.first { $0.id == activeID }?.id : nil
        for tab in loose where tab.id != staying {
            close(tab)
        }
    }
}

extension SideBar {
    /// The hairline above New Tab, with Clear at its right while there is
    /// something under it to clear.
    var looseRule: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Palette.ink.opacity(0.09))
                .frame(height: 1)
            if browser.tabs.contains(where: { $0.pin == nil && $0.bookmark == nil && !$0.isBlank }) {
                ClearLoose { browser.clearLoose() }
            }
        }
        .padding(.horizontal, SideBar.inset)
        .frame(height: SideBar.ruleHeight)
    }
}

private struct ClearLoose: View {
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text("Clear")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hovering ? Palette.ink.opacity(0.85) : Palette.quiet)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Close the other tabs. Click again to close the one you are on.")
        .animation(Motion.quick, value: hovering)
    }
}
