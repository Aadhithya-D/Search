import AppKit
import Foundation

// Fork: File › Export Passwords… writes every kept password to a CSV
// (url, username, password) that Chrome, Firefox, Arc, Ardia and the rest
// can import.
//
// Only Search can read its keychain items without a question for each one —
// another program asks once per password, and "Always Allow" covers only that
// one. So the export is done here, behind the same proof the Settings list
// asks before showing a password (Vault.prove).
//
// The file holds every password in the clear. It is written readable by you
// alone, and nothing else of the app's touches it; the announcement says to
// delete it once the other browser has it.

extension Vault {
    /// Every kept login as CSV text, and how many couldn't be read.
    static func csv() -> (text: String, count: Int, unreadable: Int) {
        func field(_ value: String) -> String {
            value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : value
        }
        var lines = ["url,username,password"]
        var unreadable = 0
        for kept in all() {
            let login = Login(host: kept.host, user: kept.user, password: "", used: kept.used, clear: kept.clear)
            guard let password = secret(for: login), !password.isEmpty else {
                unreadable += 1
                continue
            }
            let url = (kept.clear ? "http://" : "https://") + kept.host + "/"
            lines.append([url, kept.user, password].map(field).joined(separator: ","))
        }
        return (lines.joined(separator: "\n") + "\n", lines.count - 1, unreadable)
    }
}

extension Browser {
    /// File › Export Passwords…
    func exportPasswords() {
        guard !Vault.all().isEmpty else {
            announce("No passwords are kept")
            return
        }
        Vault.prove("export your saved passwords") { [weak self] ok in
            guard ok, let self else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Search Passwords.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.message = "Every saved password, readable by anyone who opens the file. Delete it once it's imported."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let (text, count, unreadable) = Vault.csv()
                let written = Self.writePrivately(text, to: url)
                DispatchQueue.main.async {
                    guard written else {
                        self.announce("The passwords couldn't be saved there")
                        return
                    }
                    let missed = unreadable > 0 ? ", \(unreadable) couldn't be read" : ""
                    self.announce("Exported \(count) passwords\(missed) — delete the file once imported", file: url)
                }
            }
        }
    }

    /// Made readable by its owner alone before a byte of it is written.
    private static func writePrivately(_ text: String, to url: URL) -> Bool {
        let files = FileManager.default
        try? files.removeItem(at: url)
        guard files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: url)
        else { return false }
        defer { try? handle.close() }
        return (try? handle.write(contentsOf: Data(text.utf8))) != nil
    }
}
