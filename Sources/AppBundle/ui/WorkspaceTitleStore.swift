import Common
import Foundation

/// Workspace titles set from the menu bar.
///
/// Kept in `UserDefaults` rather than written back into the config: the config is hand authored,
/// carries comments, and is reloaded from disk, so rewriting it to record a rename would risk the
/// user's own formatting. A title is presentation only, so it does not belong to the tree either.
@MainActor
enum WorkspaceTitleStore {
    private static let userDefaultsKey = "workspaceTitles"
    /// `Workspace.title` is read for every workspace on every tray refresh, so the dictionary is
    /// kept in memory and written through instead of being decoded each time
    private static var cached: [String: String]? = nil

    static var overrides: [String: String] {
        if let cached { return cached }
        // Tests must not read or write the real titles the user has saved
        let loaded = isUnitTest
            ? [:]
            : UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        cached = loaded
        return loaded
    }

    static func title(ofWorkspace name: String) -> String? { overrides[name] }

    /// A blank title removes the override, which falls the workspace back to its configured title,
    /// or to its name when it has none
    static func setTitle(_ title: String?, ofWorkspace name: String) {
        var updated = overrides
        switch title?.trim().takeIf({ !$0.isEmpty }) {
            case let title?: updated[name] = title
            case nil: updated.removeValue(forKey: name)
        }
        write(updated)
    }

    static func resetAll() { write([:]) }

    private static func write(_ overrides: [String: String]) {
        cached = overrides
        if !isUnitTest {
            UserDefaults.standard.setValue(overrides, forKey: userDefaultsKey)
        }
    }
}
