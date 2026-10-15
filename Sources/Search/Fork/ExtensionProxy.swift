import Foundation
import Network
import WebKit

// Fork: chrome.proxy, for a VPN extension — Proton VPN — to send the
// browsing through its server. What it sets is one server and the sites
// that go around it (Chrome's "fixed_servers"); WebKit takes the same as a
// proxy configuration on each website store, the space's own included, and
// on every store made while it is on. The extension's sign-in to its server
// is asked of its own onAuthRequired listener as the setting is made (see
// `shim`), and again now and then while it stays on, since it rotates.
//
// Private windows and tabs take it too while extensions may run there
// (Settings › Extensions), as Chrome's incognito inherits a "regular"
// setting from an extension allowed in it.
//
// What doesn't come: a PAC script (Proton's "only these sites"), which is
// refused as before; and WebRTC, which WebKit gives no way to keep to the
// proxy. Nothing is written down: quitting turns it off, and the
// extension shows itself disconnected at the next launch.

@MainActor
enum ExtensionProxy {
    struct Unsupported: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    /// The extension whose proxy is on, and what it set.
    private static var owner: String?
    private static var value: [String: Any]?
    private static var credentials: Credentials?
    private static var configurations: [ProxyConfiguration] = []

    private struct Credentials: Equatable {
        let username: String
        let password: String
    }

    /// chrome.proxy.settings' get, set and clear; nil for any other setting.
    static func answer(_ api: String, _ details: [String: Any], extension id: String) throws -> [String: Any]? {
        switch api {
        case "setting.set:proxy.settings":
            try set(details, by: id)
            return [:]
        case "setting.clear:proxy.settings":
            if owner == id { turnOff() }
            return [:]
        case "setting.get:proxy.settings":
            guard let owner, let value else {
                return ["value": ["mode": "system"], "levelOfControl": "controllable_by_this_extension"]
            }
            return ["value": value, "levelOfControl": owner == id ? "controlled_by_this_extension" : "controlled_by_other_extensions"]
        default:
            return nil
        }
    }

    /// An extension turned off or removed takes its proxy with it.
    static func forget(_ id: String) {
        if owner == id { turnOff() }
    }

    /// Private windows' and tabs' stores, each gone with its last tab.
    private static let privateStores = NSHashTable<WKWebsiteDataStore>.weakObjects()

    /// Whether extensions may run in private windows (Settings › Extensions).
    private static var inPrivate: Bool { Store.settings.bool(forKey: "extensions.private") }

    /// A store made while the proxy is on — a space's, the first time it is
    /// asked for, or a private window's or tab's — starts with it.
    static func dress(_ store: WKWebsiteDataStore) {
        if store.isPersistent {
            if !configurations.isEmpty { store.proxyConfigurations = configurations }
        } else {
            privateStores.add(store)
            if inPrivate, !configurations.isEmpty { store.proxyConfigurations = configurations }
        }
    }

    /// Extensions allowed in private windows, or no longer: the proxy goes
    /// there too, or comes away.
    static func privateChanged() {
        for store in privateStores.allObjects { store.proxyConfigurations = inPrivate ? configurations : [] }
    }

    private static func set(_ details: [String: Any], by id: String) throws {
        let asked = details["value"] as? [String: Any] ?? [:]
        let made: Credentials? = (details["credentials"] as? [String: Any]).flatMap { given in
            guard let username = given["username"] as? String, !username.isEmpty else { return nil }
            return Credentials(username: username, password: given["password"] as? String ?? "")
        }
        let wanted = try configurations(for: asked, credentials: made)
        guard !wanted.isEmpty else {
            if owner == id || owner == nil { turnOff() }
            return
        }
        // The same server signed in the same way: nothing to do. Set again
        // to refresh its sign-in, it often is.
        if owner == id, let value, NSDictionary(dictionary: value).isEqual(to: asked), credentials == made { return }
        owner = id
        value = asked
        credentials = made
        configurations = wanted
        apply()
    }

    private static func turnOff() {
        owner = nil
        value = nil
        credentials = nil
        guard !configurations.isEmpty else { return }
        configurations = []
        apply()
    }

    private static func apply() {
        for store in Spaces.everyStore { store.proxyConfigurations = configurations }
        privateChanged()
    }

    /// What WebKit is told for what the extension set: one server, or none.
    private static func configurations(for value: [String: Any], credentials: Credentials?) throws -> [ProxyConfiguration] {
        switch value["mode"] as? String ?? "system" {
        case "direct", "system", "auto_detect":
            return []
        case "fixed_servers":
            break
        case "pac_script":
            throw Unsupported(why: "Search can send everything through the VPN, but not only some sites. Turn off the list of sites to include, and connect again.")
        default:
            throw Unsupported(why: "Search doesn't support that kind of proxy.")
        }
        let rules = value["rules"] as? [String: Any] ?? [:]
        let named = rules["singleProxy"] ?? rules["proxyForHttps"] ?? rules["proxyForHttp"] ?? rules["fallbackProxy"]
        guard let server = named as? [String: Any],
              let host = (server["host"] as? String)?.trimmingCharacters(in: .whitespaces), !host.isEmpty
        else { throw Unsupported(why: "The proxy names no server.") }
        let scheme = (server["scheme"] as? String ?? "http").lowercased()
        let number = (server["port"] as? Int) ?? (scheme == "https" ? 443 : scheme.hasPrefix("socks") ? 1080 : 80)
        guard (1...65535).contains(number), let port = NWEndpoint.Port(rawValue: UInt16(number)) else {
            throw Unsupported(why: "The proxy's port isn't one.")
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)

        var made: ProxyConfiguration
        switch scheme {
        case "https":
            // Spoken to over TLS, as Proton's servers are.
            made = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: NWProtocolTLS.Options())
        case "http":
            made = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case "socks5":
            made = ProxyConfiguration(socksv5Proxy: endpoint)
        default:
            throw Unsupported(why: "Search doesn't support \(scheme) proxies.")
        }
        made.excludedDomains = around(rules["bypassList"] as? [String] ?? [])
        // A server that stops answering mustn't let pages quietly go around
        // it, from the address it was there to hide.
        made.allowFailover = false
        if let credentials { made.applyCredential(username: credentials.username, password: credentials.password) }
        return [made]
    }

    /// Chrome's bypass list as domains: "*.example.com" is example.com and
    /// what is under it. "<local>" and address ranges have no domain to
    /// name and are left out.
    private static func around(_ list: [String]) -> [String] {
        var domains: [String] = []
        for entry in list {
            var domain = entry.trimmingCharacters(in: .whitespaces).lowercased()
            guard !domain.isEmpty, domain != "<local>", !domain.contains("/") || domain.contains("://") else { continue }
            if let range = domain.range(of: "://") { domain = String(domain[range.upperBound...]) }
            while domain.hasPrefix("*") || domain.hasPrefix(".") { domain.removeFirst() }
            // A port after it names no other domain.
            if !domain.hasPrefix("["), let colon = domain.lastIndex(of: ":") { domain = String(domain[..<colon]) }
            if !domain.isEmpty, !domains.contains(domain) { domains.append(domain) }
        }
        return domains
    }

    /// In the extension's background: its onAuthRequired listeners heard as
    /// they are added, and asked for the server's sign-in as a proxy is set,
    /// which goes to Search with it. WebKit has no onAuthRequired that can
    /// answer, so this is the only way the sign-in reaches the server.
    nonisolated static let shim = #"""
    if (background && chrome.proxy && chrome.proxy.settings && chrome.webRequest) {
      const heard = new Set();
      let auth = chrome.webRequest.onAuthRequired;
      if (!auth || typeof auth.addListener !== "function") {
        auth = event();
        put(chrome.webRequest, "onAuthRequired", auth);
      }
      const addAuth = auth.addListener.bind(auth);
      const dropAuth = typeof auth.removeListener === "function" ? auth.removeListener.bind(auth) : () => {};
      put(auth, "addListener", (listener, filter, spec) => {
        if (typeof listener === "function") heard.add(listener);
        try { return addAuth(listener, filter, spec); } catch (e) {}
      });
      put(auth, "removeListener", (listener) => { heard.delete(listener); try { dropAuth(listener); } catch (e) {} });
      put(auth, "hasListener", (listener) => heard.has(listener));
      put(auth, "hasListeners", () => heard.size > 0);

      // As Chrome asks when the server answers 407. Only an answer with a
      // sign-in counts; one that gives none, or none in time, is no sign-in.
      const signIn = (host, port) => new Promise((resolve) => {
        const listeners = [...heard];
        if (!listeners.length) return resolve(null);
        let left = listeners.length, done = false;
        const finish = (answer) => {
          if (done) return;
          const given = answer && answer.authCredentials;
          if (given && given.username) { done = true; resolve({ username: String(given.username), password: String(given.password || "") }); }
          else if (--left <= 0) { done = true; resolve(null); }
        };
        setTimeout(() => { if (!done) { done = true; resolve(null); } }, 20000);
        const details = {
          requestId: "search-proxy-" + Math.random().toString(36).slice(2), url: "https://" + host + "/", method: "GET",
          frameId: 0, parentFrameId: -1, tabId: -1, type: "other", timeStamp: Date.now(),
          isProxy: true, scheme: "basic", realm: "", challenger: { host, port }, statusCode: 407,
          statusLine: "HTTP/1.1 407 Proxy Authentication Required", responseHeaders: [],
        };
        for (const listener of listeners) {
          let once = false;
          const reply = (answer) => { if (!once) { once = true; finish(answer); } };
          try {
            const result = listener(details, reply);
            // Blocking, it answers by returning; asyncBlocking, by calling back.
            if (result && result.authCredentials) reply(result);
            else if (result && typeof result.then === "function") result.then((a) => { if (a && a.authCredentials) reply(a); }, () => {});
          } catch (e) { reply(null); }
        }
      });

      const serverOf = (value) => {
        const rules = value && value.mode === "fixed_servers" && value.rules;
        return rules ? (rules.singleProxy || rules.proxyForHttps || rules.proxyForHttp || rules.fallbackProxy || null) : null;
      };
      let on = null;
      const send = async (details) => {
        const server = serverOf(details && details.value);
        const credentials = server && server.host ? await signIn(server.host, server.port || 443) : null;
        await native("setting.set:proxy.settings", [{ ...(details || {}), credentials }]);
        on = server ? { value: details.value } : null;
      };
      const proxySettings = chrome.proxy.settings;
      const clearProxy = proxySettings.clear;
      put(proxySettings, "set", (details, callback) => {
        const promise = send(details);
        if (typeof callback !== "function") return promise;
        promise.then(() => callback(), (error) => withLastError(error, callback));
      });
      put(proxySettings, "clear", (details, callback) => { on = null; return clearProxy(details, callback); });
      // The sign-in rotates: asked for again while the proxy is on.
      setInterval(() => { if (on) send(on).catch(() => {}); }, 4 * 60 * 1000);
      // A background started again while it is on — WebKit sleeps idle ones
      // — signs in afresh once the extension has its listener back.
      setTimeout(() => {
        if (on || !heard.size) return;
        native("setting.get:proxy.settings", [{}]).then((now) => {
          if (!on && now && now.levelOfControl === "controlled_by_this_extension" && serverOf(now.value)) send({ value: now.value }).catch(() => {});
        }, () => {});
      }, 5000);
    }
    """#
}
