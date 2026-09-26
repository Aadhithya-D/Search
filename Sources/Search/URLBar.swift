import SwiftUI

/// The address, always there, across the top of the page.
///
/// It used to arrive only when asked for — ⌘L, or a tab with nowhere to go —
/// and then it stood in the middle and the page dimmed behind it. The address
/// of the page you are on is not something to summon. This keeps it in a bar:
/// the page's address while you read, and the same field as before once you
/// click it or press ⌘L. Suggestions hang under the bar rather than under a
/// field in the middle (see OfferList).
struct URLBar: View {
    @ObservedObject var browser: Browser
    /// Beside the column the bar is the lights' own row, so the page starts
    /// where the pins do. Under the strip, and when the column is folded, it
    /// is the shorter band.
    var tall = false

    /// The shorter band. The tall one is the strip's own height.
    static let height: CGFloat = 40

    @State private var shake: CGFloat = 0
    @State private var refused = false

    var body: some View {
        pill
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: tall ? Metrics.strip : URLBar.height)
            .background(Palette.ground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
    }

    private var pill: some View {
        HStack(spacing: 8) {
            if let url = browser.active?.address, !browser.fieldShowing {
                Image(systemName: url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(url.scheme == "https" ? Palette.muted : Palette.unsafe)
            }

            if browser.fieldShowing {
                AddressField(browser: browser, point: 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
            } else {
                Text(shown)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(refused ? Color.red.opacity(0.35) : Palette.hairline, lineWidth: 1)
        )
        .modifier(Shake(travel: shake))
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

    /// The address as the bar shows it at rest: the host and the path, and
    /// the query when there is one. Clicking it puts the whole address in
    /// the field, scheme and all.
    private var shown: String {
        guard let url = browser.active?.address else { return "Enter a web address" }
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
