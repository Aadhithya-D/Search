import Foundation
import JavaScriptCore
import WebKit
import XCTest
@testable import Search

@MainActor
final class ExtensionProxyTests: XCTestCase {
    private let proton = "jplgfhpmjnbigmhklmmbgecoobifkmpa"

    override func tearDown() {
        MainActor.assumeIsolated { ExtensionProxy.forget(proton) }
        super.tearDown()
    }

    /// The whole Chrome layer, with the proxy's part in it, still parses:
    /// one stray character there and no extension starts.
    @available(macOS 15.4, *)
    func testShimStillParses() throws {
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, error in thrown = error?.toString() }
        context.setObject(ExtensionShims.script, forKeyedSubscript: "source" as NSString)
        context.evaluateScript("new Function(source)")
        XCTAssertNil(thrown)
    }

    func testOneServerIsSetAndReadBack() throws {
        let details: [String: Any] = [
            "value": ["mode": "fixed_servers",
                      "rules": ["singleProxy": ["scheme": "https", "host": "node-ch-01.protonvpn.net", "port": 4443],
                                "bypassList": ["<local>", "*.proton.me", "192.168.0.0/16"]]],
            "credentials": ["username": "user", "password": "secret"],
        ]
        _ = try ExtensionProxy.answer("setting.set:proxy.settings", details, extension: proton)
        let mine = try XCTUnwrap(ExtensionProxy.answer("setting.get:proxy.settings", [:], extension: proton))
        XCTAssertEqual(mine["levelOfControl"] as? String, "controlled_by_this_extension")
        XCTAssertEqual((mine["value"] as? [String: Any])?["mode"] as? String, "fixed_servers")
        // Never the sign-in: that was the extension's to give, not to read back.
        XCTAssertNil(mine["credentials"])
        let theirs = try XCTUnwrap(ExtensionProxy.answer("setting.get:proxy.settings", [:], extension: "another"))
        XCTAssertEqual(theirs["levelOfControl"] as? String, "controlled_by_other_extensions")
        XCTAssertEqual(Store.websites.proxyConfigurations.count, 1)

        _ = try ExtensionProxy.answer("setting.clear:proxy.settings", [:], extension: proton)
        let cleared = try XCTUnwrap(ExtensionProxy.answer("setting.get:proxy.settings", [:], extension: proton))
        XCTAssertEqual(cleared["levelOfControl"] as? String, "controllable_by_this_extension")
        XCTAssertTrue(Store.websites.proxyConfigurations.isEmpty)
    }

    func testOnlySomeSitesIsRefused() {
        let details: [String: Any] = ["value": ["mode": "pac_script", "pacScript": ["data": "function FindProxyForURL() {}"]]]
        XCTAssertThrowsError(try ExtensionProxy.answer("setting.set:proxy.settings", details, extension: proton))
        XCTAssertTrue(Store.websites.proxyConfigurations.isEmpty)
    }

    func testAnExtensionTurnedOffTakesItsProxy() throws {
        let details: [String: Any] = ["value": ["mode": "fixed_servers",
                                                "rules": ["singleProxy": ["scheme": "http", "host": "proxy.example", "port": 8080]]]]
        _ = try ExtensionProxy.answer("setting.set:proxy.settings", details, extension: proton)
        XCTAssertEqual(Store.websites.proxyConfigurations.count, 1)
        ExtensionProxy.forget(proton)
        XCTAssertTrue(Store.websites.proxyConfigurations.isEmpty)
    }

    func testPrivateStoresFollowTheExtensionsSwitch() throws {
        let key = "extensions.private"
        let before = Store.settings.object(forKey: key)
        defer { Store.settings.set(before, forKey: key) }
        let store = WKWebsiteDataStore.nonPersistent()
        ExtensionProxy.dress(store)
        let details: [String: Any] = ["value": ["mode": "fixed_servers",
                                                "rules": ["singleProxy": ["scheme": "https", "host": "node.example", "port": 4443]]]]

        Store.settings.set(false, forKey: key)
        _ = try ExtensionProxy.answer("setting.set:proxy.settings", details, extension: proton)
        XCTAssertTrue(store.proxyConfigurations.isEmpty)

        Store.settings.set(true, forKey: key)
        ExtensionProxy.privateChanged()
        XCTAssertEqual(store.proxyConfigurations.count, 1)
        // And one opened while it is on starts with it.
        let later = WKWebsiteDataStore.nonPersistent()
        ExtensionProxy.dress(later)
        XCTAssertEqual(later.proxyConfigurations.count, 1)

        ExtensionProxy.forget(proton)
        XCTAssertTrue(store.proxyConfigurations.isEmpty)
    }

    func testOtherSettingsAreNotTheProxys() throws {
        XCTAssertNil(try ExtensionProxy.answer("setting.get:privacy.network.webRTCIPHandlingPolicy", [:], extension: proton))
    }
}
