import SwiftUI
import AppKit

// Fork: a keyword in the address field, as in Zen. Type it, press space, and
// the field becomes a search of that one site — the name sits in the field,
// and what you type after goes where %s is in its address.

struct SearchAlias: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var template: String
    var keyword: String
}

extension Preferences {
    /// A letter, then a space, and nothing else in the field: that keyword's
    /// search. Anything after the space, from a paste, is the query.
    func takeKeyword(_ text: String) -> (alias: SearchAlias, rest: String)? {
        guard let space = text.firstIndex(where: { $0 == " " || $0 == "\u{00a0}" }) else { return nil }
        let key = String(text[..<space])
        guard !key.isEmpty else { return nil }
        let rest = String(text[text.index(after: space)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return searchAliases
            .first { $0.keyword.compare(key, options: .caseInsensitive) == .orderedSame }
            .map { ($0, rest) }
    }

    /// Puts one in, or writes over the one with this id. A keyword already
    /// used by another is left as it was, and this returns false.
    @discardableResult
    func saveAlias(_ alias: SearchAlias) -> Bool {
        let word = alias.keyword.lowercased()
        if searchAliases.contains(where: { $0.id != alias.id && $0.keyword.caseInsensitiveCompare(word) == .orderedSame }) {
            return false
        }
        var next = alias
        next.keyword = word
        if let index = searchAliases.firstIndex(where: { $0.id == alias.id }) {
            searchAliases[index] = next
        } else {
            searchAliases.append(next)
        }
        return true
    }

    func removeAlias(_ id: SearchAlias.ID) {
        searchAliases.removeAll { $0.id == id }
    }
}

extension Browser {
    /// The field is a search of this site until Return, Escape, or a backspace
    /// that has nothing left to delete.
    func engageKeyword(_ alias: SearchAlias, query: String) {
        searchAlias = alias
        typed = query
    }

    /// Back to an ordinary address. The keyword is what the field shows, so
    /// it can be edited or deleted.
    func releaseKeyword(restoring keyword: String) {
        searchAlias = nil
        typed = keyword
    }

    func clearKeyword() {
        searchAlias = nil
    }
}

/// The name, in the field, once its keyword has been taken.
struct KeywordMark: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(red: 0.73, green: 0.29, blue: 0.49)))
            .frame(maxWidth: 140)
    }
}

/// The list in Settings › General, under the search engine.
struct SearchKeywordsSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(spacing: 0) {
            Line(
                "Search keywords",
                "A keyword, then space, searches that site. y then space can search YouTube."
            ) {
                Pill("Add") { SearchAliasEditor.present(nil, prefs: prefs) }
            }
            ForEach(prefs.searchAliases) { alias in
                Rule()
                Line(alias.name, "\(alias.keyword)  ·  \(alias.template)") {
                    HStack(spacing: 6) {
                        Pill("Edit") { SearchAliasEditor.present(alias, prefs: prefs) }
                        Pill("Remove", tint: .red) { prefs.removeAlias(alias.id) }
                    }
                }
            }
        }
    }
}

/// Name, address with %s, and the keyword. The same sheet the space questions use.
private enum SearchAliasEditor {
    static func present(_ existing: SearchAlias?, prefs: Preferences) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Search" : "Edit Search"
        alert.informativeText = "The address needs %s where the words go. In the address field, the keyword and then space searches there."

        let name = field(existing?.name ?? "", prompt: "Youtube")
        let template = field(existing?.template ?? "", prompt: "https://www.youtube.com/results?search_query=%s")
        let keyword = field(existing?.keyword ?? "", prompt: "y")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 132))
        let rows: [(String, NSTextField)] = [
            ("Search engine name", name),
            ("URL with %s in place of the search term", template),
            ("Keyword", keyword),
        ]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(rows.count - 1 - index) * 44
            let caption = NSTextField(labelWithString: row.0)
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .secondaryLabelColor
            caption.frame = NSRect(x: 0, y: y + 22, width: 360, height: 16)
            row.1.frame = NSRect(x: 0, y: y, width: 360, height: 22)
            box.addSubview(caption)
            box.addSubview(row.1)
        }
        alert.accessoryView = box
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name

        let done: (Bool) -> Void = { ok in
            guard ok else { return }
            let titled = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = template.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let word = keyword.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = SearchAlias(id: existing?.id ?? UUID(), name: titled, template: address, keyword: word)
            guard !titled.isEmpty, !word.isEmpty, !word.contains(where: \.isWhitespace), Engine.accepts(address) else {
                NSSound.beep()
                DispatchQueue.main.async { present(alias, prefs: prefs) }
                return
            }
            guard prefs.saveAlias(alias) else {
                NSSound.beep()
                DispatchQueue.main.async { present(alias, prefs: prefs) }
                return
            }
        }
        guard let window = Links.window else {
            done(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }

    private static func field(_ value: String, prompt: String) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.stringValue = value
        field.placeholderString = prompt
        return field
    }
}
