import Foundation
import WebKit

enum EasySwitchCompatibility {
    static let revision = "easy-switch-selected-page-3"

    // Version 1.2.2 calls loadShortcuts while registering onStartup, then
    // passes its undefined return as the listener. WebKit stops the worker
    // there, before its action handler is installed. Register commands at
    // worker startup instead; the install event must not register them twice.
    static func prepare(_ folder: URL) throws {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
              manifest["name"] as? String == "Google Account Easy Switch",
              manifest["version"] as? String == "1.2.2",
              (manifest["background"] as? [String: Any])?["service_worker"] as? String == "background.js"
        else { return }

        let file = folder.appendingPathComponent("background.js")
        guard (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              file.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        else { return }
        let source = try String(contentsOf: file, encoding: .utf8)
        let broken = "chrome.runtime.onStartup.addListener(loadShortcuts());"
        let function = "function loadShortcuts() {"
        var repaired = source
        if repaired.contains(broken), repaired.contains(function) {
            repaired = repaired.replacingOccurrences(of: broken, with: "loadShortcuts();")
                .replacingOccurrences(of: function, with: function + "\n  if (loadShortcuts.searchLoaded) return;\n  loadShortcuts.searchLoaded = true;")
        }
        // WebKit's worker lookup can yield an empty address. Use the page
        // Search actually displays for both cycling and navigation, rather
        // than letting a relative URL resolve at the extension's origin.
        repaired = repaired.replacingOccurrences(of: "chrome.action.getBadgeText({}, function (id) {", with: "searchEasySwitchAccount(function (id) {")
        if let start = repaired.range(of: "function searchEasySwitchAccount(callback) {") ?? repaired.range(of: "function updateURL(id) {"),
           let end = repaired.range(of: "\nchrome.tabs.onActivated.addListener", range: start.upperBound..<repaired.endIndex) {
            repaired.replaceSubrange(start.lowerBound..<end.lowerBound, with: navigation)
        }
        guard repaired != source else { return }
        try repaired.write(to: file, atomically: true, encoding: .utf8)
    }

    private static let navigation = #"""
    function searchEasySwitchAccount(callback) {
      chrome.runtime.sendNativeMessage("search", { api: "easySwitch.currentAccount", args: [] })
        .then(reply => callback(reply && reply.value != null ? reply.value : "?"), () => callback("?"));
    }

    function updateURL(id) {
      chrome.runtime.sendNativeMessage("search", { api: "easySwitch.update", args: [String(id)] })
        .then(reply => updateBadgeText(reply && reply.value != null ? String(reply.value) : "?"), () => updateBadgeText("?"));
    }

    """#

    // Only this extension, with its tabs permission, may use this narrow
    // bridge. It changes an account selector on the selected Google page;
    // it cannot supply an arbitrary destination or touch a hidden tab.
    @available(macOS 15.4, *) @MainActor
    static func answer(_ api: String, args: [Any], context: WKWebExtensionContext, owner: Extensions) throws -> String? {
        guard context.webExtension.manifest["name"] as? String == "Google Account Easy Switch",
              context.webExtension.manifest["version"] as? String == "1.2.2",
              context.hasPermission(.tabs)
        else { throw ExtensionShims.Unsupported(what: "This account-switch API belongs to Easy Switch") }
        guard let browser = owner.browser, let tab = browser.active,
              !tab.shy || context.hasAccessToPrivateData,
              let url = tab.built?.url ?? tab.address,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host()?.lowercased(),
              host == "google.com" || host.hasSuffix(".google.com") || host.range(of: #"(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$"#, options: .regularExpression) != nil
        else { return nil }
        if api == "easySwitch.currentAccount" { return account(in: url) ?? "0" }
        guard api == "easySwitch.update", let account = args.first as? String,
              let destination = switching(url, to: account)
        else { return nil }
        tab.go(to: destination)
        return account
    }

    static func account(in url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let range = parts.percentEncodedPath.range(of: #"/u/[0-9]+/"#, options: .regularExpression) {
            return String(parts.percentEncodedPath[range].dropFirst(3).dropLast())
        }
        return parts.queryItems?.first { $0.name == "authuser" }?.value
    }

    static func switching(_ url: URL, to account: String) -> URL? {
        guard !account.isEmpty, account.allSatisfy({ $0.isASCII && $0.isNumber }),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let range = parts.percentEncodedPath.range(of: #"/u/[0-9]+/"#, options: .regularExpression) {
            parts.percentEncodedPath.replaceSubrange(range, with: "/u/\(account)/")
        } else {
            var query = parts.queryItems ?? []
            query.removeAll { $0.name == "authuser" }
            query.append(URLQueryItem(name: "authuser", value: account))
            parts.queryItems = query
        }
        return parts.url
    }
}
