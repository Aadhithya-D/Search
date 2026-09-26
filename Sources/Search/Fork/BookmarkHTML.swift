import AppKit
import UniformTypeIdentifiers

// Fork: bookmarks from an exported HTML file — the Netscape format every
// browser writes — filed as a folder named after the file, beside the
// imports upstream already has from Chromium browsers.

extension Browser {
    /// A Netscape bookmarks file, as Chrome, Safari, and Firefox export one.
    func importBookmarksHTML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "A bookmarks file exported from Chrome, Safari, or Firefox."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .utf16))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        guard let text else {
            announce("Couldn't read that file")
            return
        }
        let found = BookmarkHTML.read(text)
        let count = Bookmarks.count(found)
        guard !found.isEmpty, count > 0 else {
            announce("No bookmarks in that file")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        bookmarks.take(found, from: name)
        announce(count == 1 ? "1 bookmark from \(name)" : "\(count) bookmarks from \(name)")
    }
}

/// A Netscape bookmarks file, the HTML Chrome, Safari, and Firefox write
/// when you export. Folders are `H3` headings, pages are `A` links, and a
/// `DL` is the list inside the heading that came just before it.
enum BookmarkHTML {
    static func read(_ html: String) -> [Bookmark] {
        // The heading is written before the list it names. The name is kept
        // on that list, so a folder inside it can have a heading of its own
        // without erasing the outer one.
        struct Level {
            var name: String?
            var nodes: [Bookmark] = []
        }
        var stack = [Level(name: nil)]
        var pending: String?
        var i = html.startIndex
        while i < html.endIndex {
            if html[i] != "<" {
                i = html.index(after: i)
                continue
            }
            if html[i...].hasPrefix("<!--") {
                if let end = html.range(of: "-->", range: i..<html.endIndex) {
                    i = end.upperBound
                    continue
                }
            }
            guard let tagEnd = html[i...].firstIndex(of: ">") else { break }
            let raw = String(html[html.index(after: i)..<tagEnd])
            let lower = raw.lowercased()
            let name = lower.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first.map(String.init) ?? ""
            let closing = lower.hasPrefix("/")
            i = html.index(after: tagEnd)
            if closing {
                if name == "dl", stack.count > 1 {
                    let done = stack.removeLast()
                    if let title = done.name {
                        let folder = title.isEmpty ? "Folder" : title
                        stack[stack.count - 1].nodes.append(Bookmark(title: folder, url: nil, children: done.nodes))
                    } else {
                        stack[stack.count - 1].nodes.append(contentsOf: done.nodes)
                    }
                }
                continue
            }
            if name == "dl" {
                stack.append(Level(name: pending))
                pending = nil
            } else if name == "h3" {
                let (text, next) = readText(html, from: i, until: "h3")
                pending = plain(text)
                i = next
            } else if name == "a" {
                let (text, next) = readText(html, from: i, until: "a")
                i = next
                guard let href = attribute("href", in: raw),
                      let url = URL(string: decode(href)),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https"
                else { continue }
                let title = plain(text)
                let name = title.isEmpty ? (url.host ?? url.absoluteString) : title
                stack[stack.count - 1].nodes.append(Bookmark(title: name, url: url.absoluteString, children: nil))
            }
        }
        return stack.first?.nodes ?? []
    }

    private static func readText(_ html: String, from start: String.Index, until tag: String) -> (String, String.Index) {
        let close = "</" + tag
        var j = start
        while j < html.endIndex {
            if html[j] == "<", String(html[j...].prefix(close.count)).lowercased() == close {
                let raw = String(html[start..<j])
                let next = html[j...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
                return (raw, next)
            }
            j = html.index(after: j)
        }
        return ("", html.endIndex)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let lower = tag.lowercased()
        var search = lower.startIndex
        while let found = lower.range(of: name, range: search..<lower.endIndex) {
            let beforeOK = found.lowerBound == lower.startIndex
                || !lower[lower.index(before: found.lowerBound)].isLetter
                    && !lower[lower.index(before: found.lowerBound)].isNumber
            var i = found.upperBound
            while i < tag.endIndex, tag[i] == " " || tag[i] == "\t" { i = tag.index(after: i) }
            if beforeOK, i < tag.endIndex, tag[i] == "=" {
                i = tag.index(after: i)
                while i < tag.endIndex, tag[i] == " " || tag[i] == "\t" { i = tag.index(after: i) }
                guard i < tag.endIndex else { return nil }
                let quote = tag[i]
                if quote == "\"" || quote == "'" {
                    let start = tag.index(after: i)
                    guard let end = tag[start...].firstIndex(of: quote) else { return nil }
                    return String(tag[start..<end])
                }
                let start = i
                let end = tag[start...].firstIndex(where: { $0.isWhitespace || $0 == ">" }) ?? tag.endIndex
                return String(tag[start..<end])
            }
            search = found.upperBound
        }
        return nil
    }

    private static func plain(_ text: String) -> String {
        var out = ""
        var skipping = false
        for character in text {
            if character == "<" { skipping = true; continue }
            if character == ">" { skipping = false; continue }
            if !skipping { out.append(character) }
        }
        return decode(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ text: String) -> String {
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semi = text[i...].firstIndex(of: ";"), text.distance(from: i, to: semi) <= 12 {
                let token = String(text[text.index(after: i)..<semi])
                if let character = entity(token) {
                    result.append(character)
                    i = text.index(after: semi)
                    continue
                }
            }
            result.append(text[i])
            i = text.index(after: i)
        }
        return result
    }

    private static func entity(_ token: String) -> Character? {
        switch token.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return " "
        default:
            if token.lowercased().hasPrefix("#x"),
               let value = UInt32(token.dropFirst(2), radix: 16),
               let scalar = Unicode.Scalar(value) {
                return Character(scalar)
            }
            if token.hasPrefix("#"),
               let value = UInt32(token.dropFirst(), radix: 10),
               let scalar = Unicode.Scalar(value) {
                return Character(scalar)
            }
            return nil
        }
    }
}
