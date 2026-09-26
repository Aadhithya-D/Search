import Foundation

// Fork: upstream's SidebarPosition, read as the yes/no the fork's files
// were written against (the column on the right).

extension Preferences {
    var sideRight: Bool { sidePosition == .right }
}
