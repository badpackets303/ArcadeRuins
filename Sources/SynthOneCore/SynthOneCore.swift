//  SynthOneCore — the shared framework behind both the standalone app and the
//  AUv3 plugin. DSP kernel, model, presets, tunings and the whole UI live here.
//  Currently a skeleton: P1-4/P1-5 bring in the kernel, Phase 3 the UI.

import Foundation

// Re-exported so ported files need only swap `import AudioKit` for
// `import SynthOneCore` and every AK* symbol still resolves (ADR-009).
@_exported import S1Support

public enum SynthOneCore {
    public static let version = "0.1.0"

    /// Proves the Soundpipe + S1Support link path is wired up end to end.
    public static func selfTest() -> Bool {
        AKLog("SynthOneCore \(version) selfTest")
        return SoundpipeBridge.canAllocate()
    }
}
