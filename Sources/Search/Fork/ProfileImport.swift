import SwiftUI
import AppKit
import WebKit
import SQLite3
import CommonCrypto

// Fork: another Chromium browser's profiles, one at a time, each into a
// space of your choosing — its bookmarks into that space's list, its
// cookies into that space's store so its sites stay signed in, and its
// passwords and history into the ones every space shares.
//
// Nothing of the other browser's is ever changed: its files are copied and
// the copies read (see Import.swift), and macOS is asked once for its key.

extension Chromium {
    /// One profile of a Chromium browser, as its "Local State" names it.
    struct Profile: Identifiable, Hashable {
        /// Its folder: "Default", "Profile 1", …
        let folder: String
        /// The name the browser shows for it.
        let name: String
        let source: Source

        var id: String { source.name + "/" + folder }
    }

    /// Every profile of a browser, in the order the browser lists them.
    static func profiles(of source: Source) -> [Profile] {
        let state = source.root.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: state),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = top["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }
        let order = profile["profiles_order"] as? [String] ?? cache.keys.sorted()
        let folders = order + cache.keys.filter { !order.contains($0) }.sorted()
        return folders.compactMap { folder in
            guard let info = cache[folder],
                  FileManager.default.fileExists(atPath: source.root.appendingPathComponent(folder).path)
            else { return nil }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder
            return Profile(folder: folder, name: name, source: source)
        }
    }

    /// The browsers on this Mac that keep more than one profile, or any at all.
    static func withProfiles() -> [Source] {
        known.filter { !profiles(of: $0).isEmpty }
    }

    // MARK: - cookies

    /// A profile's cookies, unwrapped with the browser's key, the ones that
    /// have already run out left behind.
    static func cookies(in profile: Profile, passphrase: String) -> [HTTPCookie] {
        let file = profile.source.root.appendingPathComponent(profile.folder).appendingPathComponent("Cookies")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("office-import-\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(at: file, to: temp)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: temp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(temp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        // From version 24 on, each value is written after a hash of its host.
        var version = 0
        var meta: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &meta, nil) == SQLITE_OK, let meta {
            if sqlite3_step(meta) == SQLITE_ROW, let text = sqlite3_column_text(meta, 0) {
                version = Int(String(cString: text)) ?? 0
            }
            sqlite3_finalize(meta)
        }
        let hashed = version >= 24

        let sql = """
        SELECT host_key, name, value, encrypted_value, path, expires_utc,
               is_secure, is_httponly, samesite, has_expires, is_persistent
        FROM cookies
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        let key = stretch(passphrase)
        let now = Date()
        var out: [HTTPCookie] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func text(_ column: Int32) -> String {
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            }
            let host = text(0)
            let name = text(1)
            guard !host.isEmpty, !name.isEmpty else { continue }
            var value = text(2)
            if value.isEmpty, let bytes = sqlite3_column_blob(statement, 3) {
                let blob = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
                guard let plain = decrypt(blob, key: key, host: hashed ? host : nil) else { continue }
                value = plain
            }
            let path = text(4).isEmpty ? "/" : text(4)
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host, .path: path, .name: name, .value: value,
            ]
            // Microseconds since 1601. A cookie with no expiry lasts the session.
            let expires = sqlite3_column_int64(statement, 5)
            let persistent = sqlite3_column_int(statement, 9) != 0 || sqlite3_column_int(statement, 10) != 0
            if persistent, expires > 0 {
                let date = Date(timeIntervalSince1970: Double(expires) / 1_000_000 - 11_644_473_600)
                guard date > now else { continue }
                properties[.expires] = date
            }
            if sqlite3_column_int(statement, 6) != 0 { properties[.secure] = "TRUE" }
            if sqlite3_column_int(statement, 7) != 0 { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            switch sqlite3_column_int(statement, 8) {
            case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
            case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
            default: break
            }
            if let cookie = HTTPCookie(properties: properties) { out.append(cookie) }
        }
        return out
    }

    /// "v10", then AES-128-CBC with an IV of sixteen spaces — the passwords'
    /// recipe — and, in newer files, the SHA-256 of the host before the value.
    /// `host` is given for those files; the hash is checked before it is cut.
    private static func decrypt(_ blob: Data, key: [UInt8], host: String?) -> String? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else {
            return String(data: blob, encoding: .utf8)
        }
        let body = [UInt8](blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = [UInt8](repeating: 0, count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
            key, key.count, iv, body, body.count, &out, out.count, &moved
        )
        guard status == kCCSuccess else { return nil }
        var plain = Data(out.prefix(moved))
        if let host {
            let bytes = Array(host.utf8)
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes, CC_LONG(bytes.count), &digest)
            guard plain.count >= 32, Array(plain.prefix(32)) == digest else { return nil }
            plain = plain.dropFirst(32)
        }
        return String(data: plain, encoding: .utf8)
    }
}

// MARK: - bringing a profile in

extension Bookmarks {
    /// Another browser's bookmarks into a space's own list, which need not be
    /// the one on screen. Kept in a folder of the profile's name unless the
    /// list was empty, as `take` does for the space on screen.
    func take(_ nodes: [Bookmark], from name: String, into id: UUID) {
        guard id != space else { _ = take(nodes, from: name); return }
        guard !nodes.isEmpty else { return }
        var list = trees[id] ?? []
        if list.isEmpty {
            list = nodes
        } else {
            list.removeAll { $0.isFolder && $0.title == name }
            list.append(.folder(name, nodes))
        }
        trees[id] = list
        save()
    }
}

extension Browser {
    /// What one profile brought.
    struct ProfileHaul {
        var bookmarks = 0
        var passwords = 0
        var places = 0
        var cookies = 0
    }

    /// One profile into one space. Everything read is read off the main
    /// thread from copies; only the landing happens here.
    /// What to bring of a profile.
    struct ProfileParts {
        var bookmarks = true
        var passwords = true
        var history = true
        var cookies = true
    }

    func takeProfile(_ profile: Chromium.Profile, into space: UUID, passphrase: String?,
                     parts: ProfileParts, then done: @escaping (ProfileHaul) -> Void) {
        let source = profile.source
        let only = profile.folder
        let cookies = parts.cookies
        DispatchQueue.global(qos: .userInitiated).async {
            let marks = parts.bookmarks ? Chromium.bookmarks(in: source, profile: only) : []
            let found = parts.passwords ? passphrase.flatMap { try? Chromium.read(source, profile: only, passphrase: $0) } : nil
            let places = parts.history ? Chromium.places(in: source, profile: only) : []
            let jar = cookies ? passphrase.map { Chromium.cookies(in: profile, passphrase: $0) } ?? [] : []
            let urls = Bookmarks.urls(marks)
            DispatchQueue.main.async {
                var haul = ProfileHaul()
                if !marks.isEmpty { self.bookmarks.take(marks, from: profile.name, into: space) }
                haul.bookmarks = Bookmarks.count(marks)

                if let found {
                    // Only accounts not kept yet: writing over one is a keychain
                    // question for each (Fork/QuietKeychain.swift).
                    for login in found.logins where !Vault.keeps(host: login.host, user: login.user)
                    && Vault.save(host: login.host, user: login.user, password: login.password, used: login.used, clear: login.clear) {
                        haul.passwords += 1
                    }
                    var never = Vault.never
                    found.never.forEach { never.insert($0) }
                    Vault.never = never
                    self.relist()
                }

                for place in places {
                    self.history.take(place.url, title: place.title, count: place.count, last: place.last)
                }
                if !places.isEmpty { self.history.settle() }
                haul.places = places.count

                let store = Spaces.store(for: space).httpCookieStore
                let group = DispatchGroup()
                for cookie in jar {
                    group.enter()
                    store.setCookie(cookie) { group.leave() }
                }
                haul.cookies = jar.count
                group.notify(queue: .main) {
                    self.objectWillChange.send()
                    done(haul)
                }

                DispatchQueue.global(qos: .utility).async {
                    let icons = Chromium.icons(in: source, profile: only, for: urls)
                    Task { @MainActor in
                        for (host, data) in icons { await Favicons.shared.adopt(data, for: host) }
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }

    /// File › Import from Another Browser…
    func askToImportProfiles() {
        ProfileImportWindow.show(for: self)
    }
}

// MARK: - the sheet

@MainActor
enum ProfileImportWindow {
    private static var window: NSWindow?

    static func show(for browser: Browser) {
        guard let parent = Links.window else { return }
        if let window { window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: ProfileImportView(browser: browser) { close() })
        let sheet = NSWindow(contentViewController: host)
        sheet.styleMask = [.titled]
        window = sheet
        parent.beginSheet(sheet)
    }

    static func close() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        self.window = nil
    }
}

struct ProfileImportView: View {
    @ObservedObject var browser: Browser
    /// The browser to start on; the first one found otherwise.
    var preset: Chromium.Source? = nil
    let close: () -> Void

    /// Where each profile goes: a space's id, or nil to leave it.
    @State private var targets: [Chromium.Profile.ID: UUID?] = [:]
    @State private var source: Chromium.Source?
    @State private var parts = Browser.ProfileParts()
    @State private var working = false
    @State private var report: [String] = []

    private var sources: [Chromium.Source] { Chromium.withProfiles() }
    private var profiles: [Chromium.Profile] { source.map(Chromium.profiles(of:)) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Another Browser")
                .font(.system(size: 15, weight: .semibold))
            if sources.isEmpty {
                Text("No Chromium browser with profiles on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Browser", selection: $source) {
                    ForEach(sources) { Text($0.name).tag(Optional($0)) }
                }
                .onChange(of: source) { _, _ in guessTargets() }

                Text("Each profile's bookmarks go into the space you choose, and its cookies into that space's sign-ins. Passwords and history are shared by every space.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(profiles) { profile in
                        GridRow {
                            Text(profile.name).frame(minWidth: 110, alignment: .leading)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Picker("", selection: binding(for: profile)) {
                                Text("Don't import").tag(UUID?.none)
                                Divider()
                                ForEach(browser.spaces) { space in
                                    Text(space.name).tag(Optional(space.id))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            if let id = targets[profile.id] ?? nil, let note = sharing(id) {
                                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 16) {
                    Toggle("Bookmarks", isOn: $parts.bookmarks)
                    Toggle("Passwords", isOn: $parts.passwords)
                    Toggle("History", isOn: $parts.history)
                    Toggle("Cookies (stay signed in)", isOn: $parts.cookies)
                }

                Text("\(source?.name ?? "The browser") is only read, never changed. macOS asks once for its keychain key.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            if !report.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report, id: \.self) { Text($0).font(.system(size: 12)) }
                }
            }

            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button(report.isEmpty ? "Cancel" : "Done", action: close)
                    .keyboardShortcut(.cancelAction)
                if report.isEmpty {
                    Button("Import", action: start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(working || !targets.values.contains { $0 != nil }
                                  || !(parts.bookmarks || parts.passwords || parts.history || parts.cookies))
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if source == nil { source = preset ?? sources.first }
            guessTargets()
        }
    }

    private func binding(for profile: Chromium.Profile) -> Binding<UUID?> {
        Binding(get: { targets[profile.id] ?? nil }, set: { targets[profile.id] = $0 })
    }

    /// A space with the profile's name is the first guess; the rest wait to be chosen.
    private func guessTargets() {
        var guesses: [Chromium.Profile.ID: UUID?] = [:]
        for profile in profiles {
            let match = browser.spaces.first { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }
            guesses[profile.id] = match?.id
        }
        targets = guesses
    }

    /// A space signed in with the first one shares its cookies.
    private func sharing(_ id: UUID) -> String? {
        guard parts.cookies, id != Space.firstID, Spaces.sharing.contains(id) else { return nil }
        return "shares sign-ins with \(browser.spaces.first?.name ?? "the first space")"
    }

    private func start() {
        guard let source else { return }
        let chosen = profiles.compactMap { profile in (targets[profile.id] ?? nil).map { (profile, $0) } }
        guard !chosen.isEmpty else { return }
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            let passphrase = Chromium.safeStorage(source)
            DispatchQueue.main.async {
                if passphrase == nil {
                    report.append("\(source.name) didn't give up its keychain key: bookmarks and history only.")
                }
                run(chosen[...], passphrase: passphrase)
            }
        }
    }

    private func run(_ left: ArraySlice<(Chromium.Profile, UUID)>, passphrase: String?) {
        guard let (profile, space) = left.first else {
            working = false
            browser.announce("Imported from \(source?.name ?? "the browser")")
            return
        }
        browser.takeProfile(profile, into: space, passphrase: passphrase, parts: parts) { haul in
            let name = browser.spaces.first { $0.id == space }?.name ?? "a space"
            var said: [String] = []
            if parts.bookmarks { said.append("\(haul.bookmarks) bookmarks") }
            if parts.passwords { said.append("\(haul.passwords) passwords") }
            if parts.history { said.append("\(haul.places) history entries") }
            if parts.cookies { said.append("\(haul.cookies) cookies") }
            report.append("\(profile.name) → \(name): " + said.joined(separator: ", "))
            run(left.dropFirst(), passphrase: passphrase)
        }
    }
}
