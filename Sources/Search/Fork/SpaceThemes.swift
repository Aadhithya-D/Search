import SwiftUI
import AppKit

// Fork: a space's own colour — a pastel and its deep twin, worn light, dark
// or as the window is — and an icon that can be an emoji as well as one of
// the symbols. The stored `tone` is the only line this adds to Space itself.

extension Space {
    enum Tone: String, Codable, CaseIterable {
        // Soft and Deep are the middle ground: the pastel taken some way
        // toward its deep twin, still worn with dark ink, and the deep colour
        // brought some way up, still worn with light ink.
        case auto, light, soft, deep, dark
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .light: return "Light"
            case .soft: return "Soft"
            case .deep: return "Deep"
            case .dark: return "Dark"
            }
        }
    }

    /// How far from the pastel (0) toward the deep colour (1) this space is
    /// worn on a window that is `dark`.
    func depth(on dark: Bool) -> CGFloat {
        switch tone ?? .auto {
        case .auto: return dark ? 1 : 0
        case .light: return 0
        case .soft: return 0.3
        case .deep: return 0.62
        case .dark: return 1
        }
    }

    /// An emoji chosen for its icon, in place of a symbol.
    var emoji: String? {
        guard let icon, !icon.isEmpty, !Spaces.icons.contains(icon) else { return nil }
        return icon
    }

    /// An icon was chosen, symbol or emoji. A space without one is a dot.
    var hasIcon: Bool { icon?.isEmpty == false }

    /// The colour's variant this space wears on a window that is `dark`.
    /// Light ink from halfway down.
    func wearsDark(on dark: Bool) -> Bool {
        depth(on: dark) >= 0.5
    }
}

extension Spaces {
    /// A space's colour, light enough to be the column and the frame around
    /// the page, and a darker twin of the same hue for a dark window. The
    /// first is the rose Arc's own sidebar wears; the rest are the soft
    /// presets from its theme picker.
    struct Tint {
        var name: String
        var light: (CGFloat, CGFloat, CGFloat)
        var dark: (CGFloat, CGFloat, CGFloat)
    }

    // Light: the pastel Arc wears, the two strongest held back a little so
    // the frame round the page never outshouts the page. Dark: the same hue,
    // low and quiet — a tint on near-black, as Arc does it, not a colour.
    static let tints: [Tint] = [
        Tint(name: "Rose", light: (0.937, 0.656, 0.665), dark: (0.220, 0.150, 0.152)),
        Tint(name: "Pink", light: (1.00, 0.796, 0.824), dark: (0.228, 0.168, 0.180)),
        Tint(name: "Peach", light: (1.00, 0.878, 0.827), dark: (0.220, 0.170, 0.150)),
        Tint(name: "Butter", light: (1.00, 0.976, 0.898), dark: (0.220, 0.208, 0.167)),
        Tint(name: "Mint", light: (0.871, 0.992, 0.922), dark: (0.150, 0.220, 0.179)),
        Tint(name: "Sky", light: (0.863, 0.953, 0.988), dark: (0.150, 0.200, 0.220)),
        Tint(name: "Periwinkle", light: (0.773, 0.776, 0.898), dark: (0.150, 0.151, 0.220)),
        Tint(name: "Mauve", light: (0.945, 0.820, 0.925), dark: (0.220, 0.150, 0.209)),
        Tint(name: "Coral", light: (0.970, 0.729, 0.679), dark: (0.232, 0.160, 0.144)),
        Tint(name: "Sea", light: (0.627, 0.824, 0.745), dark: (0.150, 0.220, 0.192)),
        Tint(name: "Sand", light: (0.925, 0.886, 0.824), dark: (0.220, 0.200, 0.167)),
        Tint(name: "Lilac", light: (0.820, 0.733, 0.910), dark: (0.184, 0.150, 0.220)),
    ]

    static func clamp(_ index: Int) -> Int {
        let count = tints.count
        guard count > 0 else { return 0 }
        return ((index % count) + count) % count
    }

    /// The column, and the thin frame the page sits in.
    static func ground(_ space: Space) -> Color {
        Color(nsColor: nsGround(space))
    }

    static func nsGround(_ space: Space) -> NSColor {
        let tint = tints[clamp(space.colour)]
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = tint.at(space.depth(on: dark))
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    /// The colour's own ink: its hue, strong enough to draw a folder in on
    /// the column — deeper on the pastel, brighter on the deep colour.
    static func accent(_ index: Int, dark: Bool) -> Color {
        let c = tints[clamp(index)].light
        let rgb = NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return dark
            ? Color(hue: hue, saturation: 0.42, brightness: 0.95)
            : Color(hue: hue, saturation: 0.62, brightness: 0.62)
    }

    /// The swatch of a colour at a depth, for the picker.
    static func swatch(_ index: Int, depth: CGFloat) -> Color {
        let c = tints[clamp(index)].at(depth)
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// A space's icon as an image, for the menus: its symbol, or its emoji
    /// drawn into one.
    @MainActor static func image(for space: Space) -> NSImage? {
        guard let emoji = space.emoji else {
            return NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil)
        }
        let text = emoji as NSString
        let font = NSFont.systemFont(ofSize: 13)
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let drawn = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2), withAttributes: attrs)
            return true
        }
    }

    /// The swatch, always the light colour, so a dot reads the same on a
    /// dark window as on a light one.
    static func swatch(_ index: Int) -> Color {
        let c = tints[clamp(index)].light
        return Color(red: c.0, green: c.1, blue: c.2)
    }
}

extension Browser {
    /// An emoji for the icon; empty takes the icon away, back to a dot.
    func setSpaceEmoji(_ id: UUID, to text: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
        spaces[at].icon = first
        Spaces.write(spaces)
    }

    func setSpaceTone(_ id: UUID, to tone: Space.Tone) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].tone = tone == .auto ? nil : tone
        Spaces.write(spaces)
    }

    func setSpaceColour(_ id: UUID, to index: Int) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].colour = Spaces.clamp(index)
        Spaces.write(spaces)
    }
}

/// A space's icon: one of the symbols, or an emoji, drawn at one size.
struct SpaceGlyph: View {
    let space: Space
    var size: CGFloat = 12

    var body: some View {
        SpaceGlyph.drawn(space.emoji ?? space.symbol, size: size)
    }

    /// A symbol's name, or an emoji — anything not a symbol is text.
    @ViewBuilder
    static func drawn(_ icon: String, size: CGFloat) -> some View {
        if Spaces.icons.contains(icon) || icon == "plus" {
            Image(systemName: icon).font(.system(size: size, weight: .medium))
        } else {
            Text(icon).font(.system(size: size + 1))
        }
    }

    /// The emoji, asked for with the Mac's own picker open beside it.
    @MainActor static func askEmoji(for space: Space, browser: Browser) {
        Ask.name("Emoji for “\(space.name)”", placeholder: "🙂", initial: space.emoji ?? "", confirm: "Use") {
            browser.setSpaceEmoji(space.id, to: $0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

extension Spaces.Tint {
    /// The pastel at 0, the deep colour at 1, and between them a straight
    /// mix — the same hue, only lower.
    func at(_ depth: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let t = min(1, max(0, depth))
        return (light.0 + (dark.0 - light.0) * t,
                light.1 + (dark.1 - light.1) * t,
                light.2 + (dark.2 - light.2) * t)
    }
}
