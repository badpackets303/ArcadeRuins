// P0-4 spike: headless AU host test.
// Covers what auval does not: out-of-process vs in-process instantiation,
// view controller vending, and actual audio output under offline rendering.

import AVFoundation
import CoreAudioKit
import AppKit

let desc = AudioComponentDescription(
    componentType: kAudioUnitType_MusicDevice,
    componentSubType: 0x73706B31,      // 'spk1'
    componentManufacturer: 0x42503033, // 'BP03'
    componentFlags: 0, componentFlagsMask: 0)

func pump(until done: () -> Bool, timeout: TimeInterval = 20) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return done()
}

func test(label: String, options: AudioComponentInstantiationOptions) {
    print("\n=== \(label) ===")

    var unit: AVAudioUnit?
    var failure: Error?
    var finished = false

    AVAudioUnit.instantiate(with: desc, options: options) { u, e in
        unit = u; failure = e; finished = true
    }
    guard pump(until: { finished }) else { print("  ✗ instantiate: TIMED OUT"); return }
    guard let avUnit = unit else {
        print("  ✗ instantiate: FAILED — \(failure.map { "\($0)" } ?? "unknown")")
        return
    }
    print("  ✓ instantiate")

    let au = avUnit.auAudioUnit

    // --- audio ---
    let engine = AVAudioEngine()
    engine.attach(avUnit)
    engine.connect(avUnit, to: engine.mainMixerNode, format: nil)

    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else { return }
    var peak: Float = 0
    do {
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        try engine.start()

        if let sched = au.scheduleMIDIEventBlock {
            let noteOn: [UInt8] = [0x90, 60, 100]
            sched(AUEventSampleTimeImmediate, 0, 3, noteOn)
        } else {
            print("  ! no scheduleMIDIEventBlock")
        }

        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                   frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var rendered: AVAudioFrameCount = 0
        while rendered < 44_100 {
            let n = min(buf.frameCapacity, 44_100 - rendered)
            let status = try engine.renderOffline(n, to: buf)
            guard status == .success else { break }
            if let ch = buf.floatChannelData {
                for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[0][i])) }
            }
            rendered += buf.frameLength
        }
        engine.stop()
        print(peak > 0.001 ? "  ✓ audio: peak \(String(format: "%.4f", peak))"
                           : "  ✗ audio: SILENT (peak \(peak))")
    } catch {
        print("  ✗ audio: \(error)")
    }

    // --- view ---
    var vc: NSObject?
    var vcDone = false
    au.requestViewController { controller in vc = controller; vcDone = true }
    if pump(until: { vcDone }, timeout: 20), let controller = vc as? NSViewController {
        let size = controller.preferredContentSize
        _ = controller.view   // force the view (and its storyboard) to load
        print("  ✓ view controller: \(type(of: controller)) preferredContentSize \(size)")
        print(controller.view.subviews.isEmpty ? "  ✗ view: NO SUBVIEWS (storyboard did not load)"
                                               : "  ✓ view: \(controller.view.subviews.count) subview(s) — storyboard loaded")
    } else {
        print("  ✗ view controller: not vended")
    }
}

let comps = AVAudioUnitComponentManager.shared().components(matching: desc)
print("Components matching aumu/spk1/BP03: \(comps.count)")
for c in comps { print("  \(c.name) — \(c.manufacturerName) — v\(c.versionString)") }

test(label: "OUT-OF-PROCESS (default)", options: [])
test(label: "IN-PROCESS (loadInProcess)", options: [.loadInProcess])
