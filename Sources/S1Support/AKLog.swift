//  Replacement for AudioKit's AKLog. 120 call sites upstream, so the shape of
//  the call is preserved exactly and only the implementation is ours (ADR-009).

import Foundation
import os.log

private let log = OSLog(subsystem: "com.badpackets303.SynthOne", category: "SynthOne")

/// Drop-in for AudioKit's `AKLog(...)`.
public func AKLog(_ items: Any?...,
                  fullname: String = #function,
                  file: String = #file,
                  line: Int = #line) {
    guard AKSettings.enableLogging else { return }
    let text = items.map { $0.map { "\($0)" } ?? "nil" }.joined(separator: " ")
    os_log("%{public}@:%{public}d:%{public}@ %{public}@",
           log: log, type: .default,
           (file as NSString).lastPathComponent, line, fullname, text)
}
