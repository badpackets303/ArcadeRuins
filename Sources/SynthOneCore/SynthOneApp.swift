//  The framework's public front door (P3-1).
//
//  Everything else in `SynthOneCore` stays at upstream's access level — `Conductor`
//  and `Manager` are `internal`, exactly as they were in the app target — because
//  making them `public` would mean adding `public` to every method that satisfies
//  an `@objc` protocol, and would put `S1Support` types into the generated Obj-C
//  header (ADR-014).
//
//  So the app target gets this instead: two calls, no knowledge of the internals.
//  P4-6 will hand the AUv3's view controller the same root view.

import UIKit
import AudioToolbox

public enum SynthOneApp {

    /// The audio unit the plugin hands a host (ADR-031).
    ///
    /// Here rather than in the extension so the tests build exactly the same unit — a test
    /// that assembled its own would pass against a unit no host ever gets. Each step is one
    /// the audio unit cannot do for itself, and the order matters.
    public static func makePluginAudioUnit(componentDescription: AudioComponentDescription) throws -> S1AudioUnit {
        // `S1AudioUnit`'s init runs `createParameters`, which builds the kernel.
        let unit = try S1AudioUnit(componentDescription: componentDescription, options: [])

        // Before the host allocates render resources. `S1NoteState::init` hands `ft_array` to
        // `sp_oscmorph2d_init`, and `allocateRenderResources` rescales every table's `sicvt` —
        // both crash on tables that do not exist yet.
        S1Wavetables.loadAndApply(to: unit)

        // The 695 shipped banks, as the host's own preset menu (P4-4). `S1AudioUnit` is Obj-C++
        // and the preset codec is Swift, so the unit cannot install them itself.
        S1FactoryPresets.install(into: unit)

        // ADR-031: host MIDI goes through the port of the standalone's MIDI chain. Set before
        // the host has the unit, so no event is ever handled the other way.
        unit.routesHostMIDI = true
        return unit
    }

    /// The desktop layout's design and minimum window sizes (P6, ADR-045), for the
    /// window and for the plugin's `preferredContentSize`.
    public static var desktopWindowSize: CGSize { S1DesktopLayout.designWindowSize }
    public static var desktopMinimumWindowSize: CGSize { S1DesktopLayout.minimumWindowSize }


    /// The root view controller, loaded from `Main.storyboard`.
    ///
    /// Note the bundle. The storyboards ship inside `SynthOneCore.framework`, not
    /// the app, so `UIMainStoryboardFile` in the app's Info.plist could not find
    /// them — the app instantiates the storyboard itself. That is also what lets
    /// the AUv3 extension load the same UI at P4-6.
    public static func makeRootViewController(layout: S1Layout = S1Layout.current) -> UIViewController {
        let bundle = Bundle(for: Manager.self)
        let storyboard = UIStoryboard(name: "Main", bundle: bundle)
        // PORT: upstream picks between the initial view controller and
        // "iPhoneParentVC" on `UIDevice.current.userInterfaceIdiom`. We always load
        // the iPad one — it is the layout the port preserves (ADR-007).
        //
        // ⚠️ This used to say "Catalyst always reports `.pad`". That stopped being
        // true at ADR-023: under *Optimize Interface for Mac* the idiom is `.mac`.
        // Nothing here changed, but `Conductor.device` had to — see the note there.
        guard let root = storyboard.instantiateInitialViewController() else {
            fatalError("Main.storyboard has no initial view controller")
        }
        // P6 (ADR-045): the desktop layout is built over the same `Manager`, from the
        // same storyboards. It lays itself out with Auto Layout, so it needs no
        // scaling container and the window is free to be any size.
        if layout == .desktop, let manager = root as? Manager {
            S1DesktopLayout.install(into: manager)
            return manager
        }
        // P3-6b: wrap it so the window can be resized. The interface keeps its exact
        // 1024×768 geometry and is scaled to fit — see `S1ScalingContainer` for why
        // scaling rather than relayout.
        return S1ScalingContainer(content: root)
    }

    /// Build the audio graph and start the engine. Call before showing the UI —
    /// `Manager` reads parameter ranges off the synth as it wires up its controls.
    /// How the audio engine should run. `offline` builds the whole graph but
    /// renders manually instead of opening an output device — see
    /// `Conductor.AudioMode` for why that distinction matters even outside tests.
    public enum AudioMode {
        case realtime
        case offline
    }

    public static func start(mode: AudioMode = .realtime) {
        // P3-3: make sure the shared folder exists and anything written into the
        // app's own container before P3-3 is moved across, *before* the UI reads
        // presets, banks or settings from it.
        do {
            try Disk.prepareSharedStorage()
        } catch {
            AKLog("could not create shared storage at \(Disk.sharedSupportURL.path): \(error)")
        }
        Disk.migrateFromContainerIfNeeded()
        // ADR-041: bring the owner's banks, presets and tunings into the App Group, once.
        // Only the standalone can: the plugin's sandbox cannot read the old folder.
        Disk.copyLegacySharedFilesIntoGroupIfNeeded()

        switch mode {
        case .realtime: Conductor.sharedInstance.start(mode: .realtime)
        case .offline:  Conductor.sharedInstance.start(mode: .offline)
        }
    }

    /// Wire the interface to the audio unit a **host** handed the plugin (P4-6).
    ///
    /// The plugin's counterpart to `start(mode:)`. No engine, no output device, no
    /// audio session — the host owns all three. Call before `makeRootViewController()`,
    /// for the same reason `start` says: `Manager` reads parameter ranges off the
    /// synth as it wires up its controls.
    public static func startHosted(audioUnit: S1AudioUnit) {
        // ADR-041: the plugin reads and writes banks, presets and tunings in the App Group
        // it shares with the app, and keeps its own settings in its container.
        do {
            try Disk.prepareSharedStorage()
        } catch {
            AKLog("could not create shared storage at \(Disk.sharedSupportURL.path): \(error)")
        }
        Conductor.sharedInstance.startHosted(audioUnit: audioUnit)
    }

    /// Stop every sounding note and reset the DSP — the Panic button, and ⌘. from
    /// the menu bar (P3-6).
    public static func panic() {
        Conductor.sharedInstance.synth?.stopAllNotes()
        Conductor.sharedInstance.synth?.resetDSP()
    }

    /// Pause the engine without tearing the graph down.
    public static func stop() {
        Conductor.sharedInstance.stopEngine()
    }

    /// TuneUp: hand a `.scala` file or a tuning URL to the Tunings panel.
    ///
    /// Returns false if the panel is not up yet, in which case the URL is picked up
    /// from `S1LaunchURLProviding` when the panel loads instead.
    @discardableResult
    public static func open(url: URL) -> Bool {
        guard let tuningsPanel = Conductor.sharedInstance.viewControllers
                .first(where: { $0 is TuningsPanelController }) as? TuningsPanelController else {
            return false
        }
        _ = tuningsPanel.openUrl(url: url)
        return true
    }
}

/// How the Tunings panel asks the app whether it was launched with a TuneUp URL.
///
/// PORT: upstream does `UIApplication.shared.delegate as? AppDelegate`. The
/// `AppDelegate` is in the app target, which the framework cannot see — and the
/// AUv3 has no app delegate at all. A protocol says what is actually needed, and
/// both hosts can answer it (or not).
public protocol S1LaunchURLProviding: AnyObject {
    /// The URL the app was launched with, consumed on first read.
    func applicationLaunchedWithURL() -> URL?
}

extension Bundle {

    /// The framework's own bundle.
    ///
    /// PORT: upstream loads every storyboard, preset bank and asset from
    /// `Bundle.main`, because they sat in the iOS app. They live in
    /// `SynthOneCore.framework` now — shared between the app and the AUv3, which is
    /// the whole reason the UI is in a framework at all. **13 call sites changed
    /// from `Bundle.main` to this**, and getting one wrong is not a compile error:
    /// it is a panel that fails to load at runtime.
    /// Public because the AUv3 extension needs it too — it loads the same factory
    /// banks, wavetables and storyboards out of the framework (P4-1, P4-6).
    public static let synthOneCore = Bundle(for: Manager.self)
}

extension UIImage {

    /// An image from the framework's asset catalogue.
    ///
    /// PORT: upstream uses `#imageLiteral(resourceName:)` and `UIImage(named:)`,
    /// both of which look in `Bundle.main`. The asset catalogue is a framework
    /// resource now, so they find nothing — and `#imageLiteral` *traps* rather than
    /// returning nil, which is how P3-1 found this: the Touch Pad panel aborted the
    /// process on its spark particle.
    static func synthOne(_ name: String) -> UIImage? {
        UIImage(named: name, in: .synthOneCore, compatibleWith: nil)
    }
}
