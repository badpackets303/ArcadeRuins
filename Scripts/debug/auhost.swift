// A minimal AUv3 host for Arcade Ruins (aumu/ruin/BP03), adapted from Spikes/P0-4-CatalystAU/Scripts/hostgui.swift.
// It instantiates the plugin out of process, puts its remote view in a window, prints the
// extension's pid, and stays open, so lldb can attach to the extension and drive its interface —
// the same position the plugin is in inside Logic, without touching Logic.
//
//   xcrun swiftc -O Scripts/debug/auhost.swift -o /tmp/auhost && /tmp/auhost
import AVFoundation
import CoreAudioKit
import AppKit

let desc = AudioComponentDescription(
    componentType: kAudioUnitType_MusicDevice,
    componentSubType: 0x7275_696E,       // 'ruin'
    componentManufacturer: 0x4250_3033,  // 'BP03'
    componentFlags: 0, componentFlagsMask: 0)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
var window: NSWindow?
var unit: AVAudioUnit?

if let component = AVAudioUnitComponentManager.shared().components(matching: desc).first {
    print("component: \(component.name) version \(component.version) sandboxSafe=\(component.isSandboxSafe)")
} else {
    print("component: not registered"); exit(1)
}

AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { avUnit, error in
    guard let avUnit = avUnit else {
        print("instantiate failed: \(error.map { "\($0)" } ?? "unknown")"); exit(1)
    }
    unit = avUnit
    avUnit.auAudioUnit.requestViewController { controller in
        guard let vc = controller as? NSViewController else { print("no view controller"); exit(1) }
        var size = vc.preferredContentSize
        if size.width < 100 || size.height < 100 { size = CGSize(width: 1024, height: 768) }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Arcade Ruins test host"
        w.contentViewController = vc
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        app.activate(ignoringOtherApps: true)
        print("window shown at \(size)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let pids = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.badpackets303.ArcadeRuins.AUv3" }
                .map { $0.processIdentifier }
            print("extension pids (NSWorkspace): \(pids)")
            print("READY")
        }
    }
}
app.run()
