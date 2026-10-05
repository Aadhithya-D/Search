import Foundation
import WebKit

enum ExtensionCompatibility {
    // Reconfirming existing grants needs no user gesture. In particular,
    // Proton closes its popup while a redundant request waits or fails.
    // Missing permissions still use the normal request and consent path.
    static let alreadyGrantedPermissions = #"""
    if (await contains({ permissions: theirs, origins })) return true;
    """#

    // Proton supports both direct and broadcast replies. WebKit omits
    // runtime.onMessage events in pages at the popup's URL, so its broadcast
    // answers never reach the waiting popup. Use Proton's direct response
    // path instead, keeping the callback/Promise and recipient unchanged.
    static let directProtonReplies = #"""
    if (runtime.id === "jplgfhpmjnbigmhklmmbgecoobifkmpa" && !inContent) {
      const index = typeof args[0] === "string" ? 1 : 0;
      const recipient = index ? args[0] : runtime.id;
      const message = args[index];
      if (recipient === runtime.id && message && message.respondTo === "broadcast"
          && typeof message.requestId === "string") {
        args[index] = { ...message, respondTo: "promise" };
      }
    }
    """#

    struct ProxyUnavailable: LocalizedError {
        var errorDescription: String? {
            "Search does not yet support extension-controlled proxies. The VPN connection was not applied."
        }
    }

    static func proxySetting(_ api: String) throws -> [String: Any]? {
        if api == "setting.set:proxy.settings" { throw ProxyUnavailable() }
        if api == "setting.get:proxy.settings" {
            return ["value": ["mode": "system"], "levelOfControl": "not_controllable"]
        }
        return nil
    }

    // Search's shim exposes a non-configurable `browser` global, identical
    // to `chrome`. A global lexical declaration of that alias fails before
    // the script executes. Leave the built-in alias in place. Only the exact
    // redundant declaration is removed; other bindings are untouched.
    static func prepare(_ folder: URL) throws {
        let files = FileManager.default
        let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        let alias = try NSRegularExpression(pattern: #"(?m)^(?:const|let)[ \t]+browser[ \t]*=[ \t]*chrome[ \t]*;[ \t]*\r?$"#)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "js",
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  url.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let edited = alias.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: ";")
            if edited != source { try edited.write(to: url, atomically: true, encoding: .utf8) }
        }
    }

    static let revision = "browser-alias-and-protocols-1"

    @MainActor @available(macOS 15.4, *)
    static func registerSchemes() {
        // These Chrome permission patterns otherwise make WebKit reject the
        // whole request, including its valid HTTP/HTTPS hosts. Registering
        // them preserves their exact schemes, hosts and paths.
        for scheme in ["ftp", "ws", "wss"] {
            WKWebExtension.MatchPattern.registerCustomURLScheme(scheme)
        }
    }
}
