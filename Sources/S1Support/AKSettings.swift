//  Replacement for AudioKit's AKSettings, trimmed to the members Synth One
//  actually touches (docs/02-audiokit-api-surface.md). Names kept — ADR-009.
//
//  Session handling is deliberately absent: `AKSettings.setSession` and
//  `AKSettings.session` belong to the standalone app only — an AU extension must
//  never configure the audio session. That split becomes the `S1AudioSession`
//  abstraction at P2-2.

import Foundation
import AVFoundation
import S1SupportC

public class AKSettings: NSObject {

    /// Whether `AKLog` emits anything.
    public static var enableLogging = true

    // These three are backed by C storage so the Obj-C++ DSP layer reads the same
    // values (ADR-010). Everything else on AKSettings is Swift-only.

    /// Global sample rate. The AU updates this from the host's format.
    public static var sampleRate: Double {
        get { ak_settings_sample_rate() }
        set { ak_settings_set_sample_rate(newValue) }
    }

    /// Global channel count.
    public static var channelCount: UInt32 {
        get { ak_settings_channel_count() }
        set { ak_settings_set_channel_count(newValue) }
    }

    /// Default ramp duration for parameter changes, in seconds.
    public static var rampDuration: Double {
        get { ak_settings_ramp_duration() }
        set { ak_settings_set_ramp_duration(newValue) }
    }

    /// iOS-only upstream; kept as an inert property so call sites port unchanged.
    public static var playbackWhileMuted: Bool = false

    /// Preferred hardware buffer length, mirroring AudioKit's enum.
    public enum BufferLength: Int {
        case shortest = 5, veryShort, short, medium, long, veryLong, huge, longest

        /// Buffer length in frames (2^rawValue).
        public var samplesCount: AVAudioFrameCount {
            AVAudioFrameCount(pow(2.0, Double(rawValue)))
        }

        /// Buffer duration in seconds.
        public var duration: Double {
            Double(samplesCount) / AKSettings.sampleRate
        }
    }

    /// Preferred buffer length. 19 call sites upstream.
    public static var bufferLength: BufferLength = .veryLong
}
