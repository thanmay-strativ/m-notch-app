import Foundation
import IOKit.pwr_mgt
import os

/// Stops idle system sleep while an agent works; lets go 10 s after the last one stops.
@MainActor
final class KeepAwake {
    static let releaseDelay: TimeInterval = 10

    var isEnabled = true {
        didSet { if !isEnabled { release() } }
    }
    private(set) var isHolding = false
    private var assertionId: IOPMAssertionID = 0
    private var releaseWork: DispatchWorkItem?
    private let logger = Logger(subsystem: "local.mnotch", category: "awake")

    func update(isBusy: Bool) {
        if isBusy && isEnabled {
            releaseWork?.cancel()
            releaseWork = nil
            acquire()
        } else if isHolding && releaseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.release() }
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
        }
    }

    private func acquire() {
        guard !isHolding else { return }
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "m_notch: an agent session is working" as CFString, &assertionId)
        isHolding = status == kIOReturnSuccess
        if !isHolding { logger.error("Keep-awake assertion failed with status \(status, privacy: .public)") }
    }

    private func release() {
        releaseWork?.cancel()
        releaseWork = nil
        guard isHolding else { return }
        IOPMAssertionRelease(assertionId)
        isHolding = false
    }
}
