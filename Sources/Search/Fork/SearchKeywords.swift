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
    /// Upstream's site shortcuts (Keyword.swift, Settings › General), read
    /// as the keywords the field turns into a search of their site.
    var searchAliases: [SearchAlias] {
        keywords.filter { Keyword.accepts($0.template) && !$0.keyword.isEmpty }.map {
            SearchAlias(id: $0.id, name: $0.name, template: $0.template, keyword: $0.keyword)
        }
    }

    /// The fork kept its keywords apart, under "search.aliases", before
    /// upstream had site shortcuts. They move over once, and that key goes.
    static func withForkKeywords(_ keywords: [Keyword]) -> [Keyword] {
        let store = Store.settings
        guard let data = store.data(forKey: "search.aliases") else { return keywords }
        let old = (try? JSONDecoder().decode([SearchAlias].self, from: data)) ?? []
        var list = keywords
        for alias in old where !list.contains(where: { $0.keyword.caseInsensitiveCompare(alias.keyword) == .orderedSame }) {
            list.append(Keyword(id: alias.id, keyword: alias.keyword.lowercased(), template: alias.template))
        }
        // Kept at once, so the old key can go.
        store.set((try? JSONEncoder().encode(list)) ?? Data(), forKey: "search.keywords")
        store.removeObject(forKey: "search.aliases")
        return list
    }

    /// A keyword, then a space, and nothing else in the field: that keyword's
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
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(red: 0.73, green: 0.29, blue: 0.49)))
            .fixedSize()
    }
}
