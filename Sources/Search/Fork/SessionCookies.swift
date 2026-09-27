import AppKit
import Security
import WebKit

// Fork: sign-ins that last only the session outlast quitting, as Chrome's
// do when it restores your tabs. A cookie with no expiry date — how AWS's
// consoles and many single sign-on pages keep you in — is thrown away by
// WebKit when the app quits; Chrome keeps it with the session. Here each
// store's are kept in the keychain, under this app's own name, where only
// this app can read them without asking, and put back at launch.
//
// Written a moment after a page finishes loading, when the app steps back,
// and once more as it quits; read once, before the first page loads.

@MainActor
enum SessionCookies {
    private static let service = Store.world.map { "com.officecommun.search.sessions (\($0))" } ?? "com.officecommun.search.sessions"
    private static var pending: DispatchWorkItem?
    private static var restored = Set<String>()

    /// Put back what was kept for a store, once per launch.
    static func restore(_ store: WKWebsiteDataStore) {
        guard store.isPersistent else { return }
        let key = name(of: store)
        guard restored.insert(key).inserted, let data = read(key),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return }
        let jar = store.httpCookieStore
        jar.getAllCookies { present in
            let there = Set(present.map { "\($0.domain)\u{1}\($0.path)\u{1}\($0.name)" })
            for fields in list {
                var properties: [HTTPCookiePropertyKey: Any] = [:]
                for (key, value) in fields { properties[HTTPCookiePropertyKey(key)] = value }
                guard let cookie = HTTPCookie(properties: properties),
                      !there.contains("\(cookie.domain)\u{1}\(cookie.path)\u{1}\(cookie.name)")
                else { continue }
                jar.setCookie(cookie)
            }
        }
    }

    /// Kept again, a moment from now; many calls in a row make one write.
    static func soon(_ browser: Browser) {
        pending?.cancel()
        let work = DispatchWorkItem { keep(browser) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Every store in use, written now. `done` once they all are.
    static func keep(_ browser: Browser, done: (() -> Void)? = nil) {
        pending?.cancel()
        pending = nil
        var stores: [String: WKWebsiteDataStore] = [:]
        for store in [Store.websites] + browser.spaces.map({ Spaces.store(for: $0.id) }) where store.isPersistent {
            stores[name(of: store)] = store
        }
        let group = DispatchGroup()
        for (key, store) in stores {
            group.enter()
            store.httpCookieStore.getAllCookies { cookies in
                let session = cookies.filter(\.isSessionOnly).map { cookie -> [String: String] in
                    var out: [String: String] = [:]
                    for (key, value) in cookie.properties ?? [:] {
                        if let text = value as? String { out[key.rawValue] = text }
                        else if let number = value as? NSNumber { out[key.rawValue] = number.stringValue }
                        else if let url = value as? URL { out[key.rawValue] = url.absoluteString }
                    }
                    // A session cookie has no expiry; never give it one.
                    out[HTTPCookiePropertyKey.expires.rawValue] = nil
                    out[HTTPCookiePropertyKey.maximumAge.rawValue] = nil
                    out[HTTPCookiePropertyKey.discard.rawValue] = "TRUE"
                    return out
                }
                if let data = try? JSONSerialization.data(withJSONObject: session) { write(data, for: key) }
                group.leave()
            }
        }
        group.notify(queue: .main) { done?() }
    }

    private static func name(of store: WKWebsiteDataStore) -> String {
        store.identifier?.uuidString ?? "default"
    }

    // MARK: - the keychain

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    private static func read(_ key: String) -> Data? {
        var asked = query(key)
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func write(_ data: Data, for key: String) {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = query(key)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Search sign-ins kept for the session"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(item as CFDictionary, nil)
    }
}

extension Browser {
    /// The kept sign-ins back before a page loads, and kept from then on.
    func followSessionCookies() {
        for store in Set([Store.websites] + spaces.map { Spaces.store(for: $0.id) }) {
            SessionCookies.restore(store)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { SessionCookies.keep(self) } }
        }
    }
}
