// P0-4 spike: put the AU's remote view in a real window so the extension's
// view actually loads, then screenshot it.

import AVFoundation
import CoreAudioKit
import AppKit

let desc = AudioComponentDescription(
    componentType: kAudioUnitType_MusicDevice,
    componentSubType: 0x73706B31, componentManufacturer: 0x42503033,
    componentFlags: 0, componentFlagsMask: 0)

let app = NSApplication.shared
app.setActivationPolicy(.regular)

var window: NSWindow?

AVAudioUnit.instantiate(with: desc, options: []) { avUnit, error in
    guard let au = avUnit?.auAudioUnit else {
        print("✗ instantiate failed: \(error.map { "\($0)" } ?? "unknown")"); exit(1)
    }
    au.requestViewController { controller in
        guard let vc = controller as? NSViewController else { print("✗ no view controller"); exit(1) }
        let size = vc.preferredContentSize
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "SpikeAU host"
        w.contentViewController = vc
        // Deterministic placement on the MAIN display so screencapture -R can find it.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let sf = screen.frame
            let target = CGPoint(x: sf.origin.x + 100, y: sf.origin.y + sf.height - 100 - w.frame.height)
            w.setFrameOrigin(target)
            print("captureRect=100,100,\(Int(w.frame.width)),\(Int(w.frame.height))")
        }
        w.makeKeyAndOrderFront(nil)
        window = w
        app.activate(ignoringOtherApps: true)
        print("✓ window shown at \(size)")
        print("screens=\(NSScreen.screens.count) frames=\(NSScreen.screens.map { $0.frame })")
        print("main=\(String(describing: NSScreen.main?.frame))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("isVisible=\(w.isVisible) onActiveSpace=\(w.isOnActiveSpace) occlusion=\(w.occlusionState.contains(.visible) ? "visible" : "occluded") frame=\(w.frame) appActive=\(NSApp.isActive)")
            print("childSubviews=\(vc.view.subviews.count) viewFrame=\(vc.view.frame)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let pid = ProcessInfo.processInfo.processIdentifier
            if let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                for i in infos where (i[kCGWindowOwnerPID as String] as? Int32) == pid {
                    if let num = i[kCGWindowNumber as String] as? Int,
                       let b = i[kCGWindowBounds as String] as? [String: Any],
                       (b["Height"] as? Double ?? 0) > 50 {
                        let x = b["X"] as? Double ?? 0, y = b["Y"] as? Double ?? 0
                        let bw = b["Width"] as? Double ?? 0, bh = b["Height"] as? Double ?? 0
                        print("windowID=\(num)")
                        print("windowRect=\(Int(x)),\(Int(y)),\(Int(bw)),\(Int(bh))")
                    }
                }
            }
            if let tree = au.parameterTree,
               let flag = tree.parameter(withAddress: 1),
               let gain = tree.parameter(withAddress: 0) {
                print(flag.value >= 0.5
                      ? "  ✓ STORYBOARD LOADED inside the AU extension (3+ subviews wired)"
                      : "  ✗ storyboard did NOT load (flag=\(flag.value))")
                print("  gain param readback = \(gain.value)")
                if let ag = tree.parameter(withAddress: 2) {
                    print(ag.value >= 0.5 ? "  ✓ App Group container writable from the extension"
                                          : "  ✗ App Group container NOT available (entitlement needs a Team ID)")
                }
            } else {
                print("  ✗ could not read parameter tree")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
        }
    }
}
app.run()
