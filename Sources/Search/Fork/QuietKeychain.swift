import Foundation
import Security

// Fork: the keychain asks as little as it can.
//
// Each saved password is an item in the login keychain that lets in the app
// that made it, and anything you allowed with "Always Allow". It knows the
// app by its signature. An ad-hoc build's signature is the hash of that one
// build, so after every rebuild each item asked again — and the list, the
// suggestions under a sign-in field and the check after a sign-in read every
// account's secret up front, one question each; Deny just brought the next.
//
// So: builds are signed with a certificate of this Mac's own ("Search Local
// Signing", see build.sh and FORK.md), which stays the same across builds, so
// "Always Allow" lasts; and lists are drawn from names alone, with the one
// secret that is used read when it is used (Vault.secret(for:)). An import
// adds only the accounts not already kept, since writing over one is a
// question too.

extension Vault {
    /// An account is kept for this site already. Asks nothing: no secret.
    static func keeps(host: String, user: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: user,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
