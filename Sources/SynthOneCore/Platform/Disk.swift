//  Replacement for the `Disk` CocoaPod (P3-1; the storage half of P3-3).
//
//  Nine files call this — presets, tuning banks, app settings. Keeping the pod's
//  API means all nine port with their `import Disk` line deleted and nothing else
//  touched (ADR-009's reasoning, applied to a third-party dependency).
//
//  Only the five entry points Synth One actually uses are here:
//  `save`/`retrieve`/`exists`/`remove`/`getURL`. The pod's `.temporary`,
//  `.sharedContainer`, image/array conveniences and append APIs are not used and
//  are not reproduced.
//
//  **Where things live (ADR-041).** Banks, presets and tunings are in the App Group's
//  container, which the app and the sandboxed plugin share. Each product keeps its own
//  `settings.json`. This is the one place either location is decided.

import Foundation

public enum Disk {

    public enum Directory {
        /// Banks, presets and tuning banks, **shared between the app and the plugin**.
        /// See `Disk.sharedSupportURL` for where this lands.
        case documents
        /// `settings.json`, which each product keeps to itself (ADR-041). See
        /// `Disk.settingsURL`.
        case settings
        /// Regenerable scratch. Used for the files handed to a share sheet.
        case caches

        public var url: URL {
            switch self {
            case .documents:
                return Disk.sharedSupportURL
            case .settings:
                return Disk.settingsURL
            case .caches:
                return Disk.cachesURL
            }
        }
    }

    /// Where `.caches` lands. A `var` for the same reason as `sharedSupportURL`: the
    /// unsandboxed test bundle would otherwise write `~/Library/Caches` (ADR-036).
    public static var cachesURL: URL = defaultCachesURL

    public static let defaultCachesURL: URL = {
        guard let url = FileManager.default.urls(for: .cachesDirectory,
                                                 in: .userDomainMask).first else {
            fatalError("no caches directory — the process has no container")
        }
        return url
    }()

    /// The App Group the app and the plugin share (ADR-041). It has to match both products'
    /// entitlements, which `DiskTests` checks.
    ///
    /// **Team-ID prefixed, the macOS form, not iOS's `group.` form.** macOS lets a process signed
    /// by team 8RSH7U3222 use a group named with that prefix without any provisioning profile
    /// listing it. The first signed build used `group.com.badpackets303.ArcadeRuins`, which
    /// Xcode's wildcard team profile does not authorise. The unsandboxed app did not care, but
    /// the sandboxed plugin never got past sandbox initialisation: it sat at 0% CPU in
    /// `_libsecinit_appsandbox` waiting on `secinitd`, and `auval` failed with -10863.
    public static let appGroupIdentifier = "8RSH7U3222.com.badpackets303.ArcadeRuins"

    /// Where banks, presets and tunings live: `Library/Application Support/SynthOne` inside
    /// the App Group's container, which both the unsandboxed app and the sandboxed plugin
    /// can read and write (ADR-041).
    ///
    /// ## How it got here
    ///
    /// Until ADR-041 this was `~/Library/Application Support/SynthOne`, resolved against the
    /// real home directory (P3-3, ADR-018), because two processes with two sandbox
    /// containers cannot share a container. The unsandboxed app could use that folder. The
    /// sandboxed plugin could see its files but never read or write them (ADR-020,
    /// ADR-038), so it offered factory presets only and every save failed silently. An App
    /// Group is the sanctioned answer and needs a Team ID (ADR-006), which arrived with the
    /// owner's Developer Program membership.
    ///
    /// A process without the group entitlement falls back to the old folder.
    ///
    /// A `var` only so tests can redirect it. Nothing in the app assigns to it —
    /// a test that wrote into the user's real preset folder would be worse than no
    /// test at all. The test bundle's principal class, `TestStorageIsolation`, points
    /// it at a temporary folder before any test runs (ADR-036).
    public static var sharedSupportURL: URL = defaultSharedSupportURL

    public static let defaultSharedSupportURL: URL = groupSupportURL ?? legacySharedSupportURL

    /// The App Group's folder, or nil when this process is not in the group.
    public static let groupSupportURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent("Library/Application Support/SynthOne", isDirectory: true)

    /// The folder the app and the plugin were meant to share before ADR-041. The standalone
    /// still keeps its settings here, and copies everything else into the group once
    /// (`copyLegacySharedFilesIntoGroupIfNeeded`).
    public static let legacySharedSupportURL: URL =
        realHomeURL.appendingPathComponent("Library/Application Support/SynthOne", isDirectory: true)

    /// Where `settings.json` lives: each product's own Application Support folder (ADR-041).
    /// For the unsandboxed app that is `legacySharedSupportURL`, so the owner's settings stay
    /// where they are. For the plugin it is inside its sandbox container, the one place it
    /// could always write. A `var` so tests can redirect it.
    public static var settingsURL: URL = defaultSettingsURL

    public static let defaultSettingsURL: URL = {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else {
            fatalError("no Application Support directory — the process has no container")
        }
        return url.appendingPathComponent("SynthOne", isDirectory: true)
    }()

    /// The user's actual home directory.
    ///
    /// `NSHomeDirectory()` answers the *container* inside a sandbox, so it cannot be
    /// used to name a location outside one. The password database is not rewritten
    /// by the sandbox.
    public static let realHomeURL: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }()

    public enum Error: Swift.Error {
        case noSuchFile(String)
        case notADirectory(URL)
    }

    /// Resolve `path` inside `directory`, creating intermediate directories.
    ///
    /// The pod accepts nested paths (`"tmp/presetcopy.json"`), and Synth One uses
    /// them, so the parent has to be created rather than assumed.
    /// Moves anything the app wrote into its own container before P3-3 into the
    /// shared folder, once.
    ///
    /// Without this, upgrading loses every user preset and tuning bank — they are
    /// still on disk, just somewhere nothing looks any more. Existing files in the
    /// shared folder always win; this only fills gaps.
    @discardableResult
    public static func migrateFromContainerIfNeeded(from legacyOverride: URL? = nil) -> Int {
        let manager = FileManager.default
        // The old location, named explicitly rather than asked for. Before P3-3 the
        // app was sandboxed and wrote into its container's Documents; it is not
        // sandboxed now (ADR-018), so `FileManager.urls(for: .documentDirectory)`
        // would answer `~/Documents` — the user's own folder, which this must never
        // touch.
        let legacy: URL
        if let legacyOverride = legacyOverride {
            legacy = legacyOverride
        } else {
            guard let bundleID = Bundle.main.bundleIdentifier else { return 0 }
            legacy = realHomeURL
                .appendingPathComponent("Library/Containers/\(bundleID)/Data/Documents", isDirectory: true)
        }
        guard manager.fileExists(atPath: legacy.path) else { return 0 }

        var moved = 0
        let names = (try? manager.contentsOfDirectory(atPath: legacy.path)) ?? []
        for name in names where name.hasSuffix(".json") {
            let source = legacy.appendingPathComponent(name)
            let destination = sharedSupportURL.appendingPathComponent(name)
            // Anything already in the shared folder wins; this only fills gaps.
            guard !manager.fileExists(atPath: destination.path) else { continue }
            do {
                try manager.createDirectory(at: sharedSupportURL, withIntermediateDirectories: true)
                try manager.moveItem(at: source, to: destination)
                moved += 1
            } catch {
                AKLog("Disk: could not migrate \(name): \(error)")
            }
        }
        if moved > 0 { AKLog("Disk: migrated \(moved) file(s) into \(sharedSupportURL.path)") }
        return moved
    }

    /// Left in the group folder once `copyLegacySharedFilesIntoGroupIfNeeded` has run.
    static let legacyCopyMarker = ".copied-from-legacy-folder"

    /// Copies the owner's banks, presets and tunings from the pre-ADR-041 folder into the App
    /// Group, **once**. Only the unsandboxed standalone can read the old folder, so only
    /// `SynthOneApp.start` calls this.
    ///
    /// - It copies and never moves, so the old folder stays as a backup.
    /// - It skips `settings.json`, which stays with the app (`settingsURL`).
    /// - On its one run it replaces whatever is already in the group: anything there came
    ///   from a plugin that had only the factory banks to start from. The marker then stops it,
    ///   so nothing saved in the group afterwards is ever replaced.
    /// - If a copy fails, no marker is left, and it tries again at the next launch.
    @discardableResult
    public static func copyLegacySharedFilesIntoGroupIfNeeded(from legacy: URL = legacySharedSupportURL,
                                                              to shared: URL = sharedSupportURL) -> Int {
        let manager = FileManager.default
        // A process outside the group resolves the shared folder to the old one: nothing to do.
        guard legacy.standardizedFileURL != shared.standardizedFileURL else { return 0 }
        let marker = shared.appendingPathComponent(legacyCopyMarker)
        guard !manager.fileExists(atPath: marker.path) else { return 0 }
        do {
            try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        } catch {
            AKLog("Disk: could not create \(shared.path): \(error)")
            return 0
        }

        var copied = 0
        var failed = false
        let names = (try? manager.contentsOfDirectory(atPath: legacy.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".json") && name != "settings.json" {
            let destination = shared.appendingPathComponent(name)
            do {
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: legacy.appendingPathComponent(name), to: destination)
                copied += 1
            } catch {
                failed = true
                AKLog("Disk: could not copy \(name) into the App Group: \(error)")
            }
        }
        if !failed {
            manager.createFile(atPath: marker.path, contents: Data())
        }
        AKLog("Disk: copied \(copied) file(s) from \(legacy.path) into \(shared.path)")
        return copied
    }

    public static func getURL(for path: String, in directory: Directory) throws -> URL {
        let url = directory.url.appendingPathComponent(path)
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        return url
    }

    /// Whether the file is there **and this process can read it** (ADR-038).
    ///
    /// Every caller asks "can I load this, or should I fall back to defaults?". The sandboxed
    /// plugin can see that `banks.json` exists in the shared folder but cannot read it
    /// (ADR-020), so a plain existence check sent it down the load path. The load then failed
    /// silently, and the plugin had no banks, no presets, and a ▶ button that crashed it.
    /// Unreadable now means absent, so the plugin loads the factory banks from its bundle.
    public static func exists(_ path: String, in directory: Directory) -> Bool {
        FileManager.default.isReadableFile(atPath: directory.url.appendingPathComponent(path).path)
    }

    /// Create the shared folder if it is not there. Called once at startup;
    /// `getURL` also creates intermediates, so this is belt and braces for the
    /// read paths that do not go through it.
    public static func prepareSharedStorage() throws {
        try FileManager.default.createDirectory(at: sharedSupportURL,
                                                withIntermediateDirectories: true)
    }

    /// Removes a file or a whole directory. Not an error if it was not there —
    /// every call site uses `try?` and means "make sure this is gone".
    public static func remove(_ path: String, from directory: Directory) throws {
        let url = directory.url.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public static func save<T: Encodable>(_ value: T, to directory: Directory, as path: String) throws {
        let url = try getURL(for: path, in: directory)
        // The pod writes `Data` through unchanged rather than JSON-encoding it,
        // and Synth One relies on that symmetry with `retrieve(_:as: Data.self)`.
        if let data = value as? Data {
            try data.write(to: url, options: .atomic)
            return
        }
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    public static func retrieve<T: Decodable>(_ path: String,
                                              from directory: Directory,
                                              as type: T.Type) throws -> T {
        let url = directory.url.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.noSuchFile(url.path)
        }
        let data = try Data(contentsOf: url)
        if type == Data.self, let data = data as? T { return data }
        return try JSONDecoder().decode(type, from: data)
    }
}
