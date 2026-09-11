// Scratch host: does selecting a user preset the plugin cannot read crash it? Out of process, as Logic
// loads it. Control first (a factory preset), then two missing user presets.
//   xcrun swiftc -O Scripts/debug/presethost.swift -o /tmp/presethost && /tmp/presethost
import AVFoundation
import Foundation

let desc = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                     componentSubType: 0x7275_696E, componentManufacturer: 0x4250_3033,
                                     componentFlags: 0, componentFlagsMask: 0)
func pids() -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", "ArcadeRuinsAU.appex/Contents/MacOS/ArcadeRuinsAU"]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.split(separator: "\n").joined(separator: ",").isEmpty ? "none" : out.split(separator: "\n").joined(separator: ",")
}
func step(_ delay: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
var keep: AVAudioUnit?

AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { avUnit, error in
    guard let avUnit = avUnit else { print("instantiate failed: \(String(describing: error))"); exit(1) }
    keep = avUnit
    let au = avUnit.auAudioUnit
    print("loaded; factory presets \(au.factoryPresets?.count ?? -1), user presets \(au.userPresets.count), supportsUserPresets \(au.supportsUserPresets); plugin pids \(pids())")
    step(2) {
        au.currentPreset = au.factoryPresets?.first
        print("control: selected factory preset '\(au.factoryPresets?.first?.name ?? "?")'")
        step(2) {
            print("  plugin pids \(pids())")
            let missing = AUAudioUnitPreset(); missing.number = -1; missing.name = "Missing Preset"
            au.currentPreset = missing
            print("selected user preset -1 'Missing Preset' (no such file)")
            step(3) {
                print("  plugin pids \(pids())")
                let unnamed = AUAudioUnitPreset(); unnamed.number = -2; unnamed.name = ""
                au.currentPreset = unnamed
                print("selected user preset -2 with an empty name")
                step(3) { print("  plugin pids \(pids())"); exit(0) }
            }
        }
    }
}
RunLoop.main.run()
