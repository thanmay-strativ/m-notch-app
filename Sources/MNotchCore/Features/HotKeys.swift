import Carbon.HIToolbox
import os

/// Option+Command shortcuts: the request keys act on the oldest waiting request and exist only while one waits;
/// Option+Command+M opens or closes the island at any time.
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable {
        case allow = 1, deny, always, option1, option2, option3, option4, toggleIsland

        static let requestActions: Set<Action> = [.allow, .deny, .always, .option1, .option2, .option3, .option4]

        var keyCode: Int {
            switch self {
            case .allow: return kVK_ANSI_Y
            case .deny: return kVK_ANSI_N
            case .always: return kVK_ANSI_A
            case .option1: return kVK_ANSI_1
            case .option2: return kVK_ANSI_2
            case .option3: return kVK_ANSI_3
            case .option4: return kVK_ANSI_4
            case .toggleIsland: return kVK_ANSI_M
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private var registered: [Action: EventHotKeyRef] = [:]
    private var unavailable: Set<Action> = []
    private var handler: EventHandlerRef?
    private let logger = Logger(subsystem: "local.mnotch", category: "hotkeys")
    private static let signature: OSType = 0x4D4E5448

    func update(requestKeys: Bool, toggleKey: Bool) {
        var wanted: Set<Action> = requestKeys ? Action.requestActions : []
        if toggleKey { wanted.insert(.toggleIsland) }
        for (action, reference) in registered where !wanted.contains(action) {
            UnregisterEventHotKey(reference)
            registered[action] = nil
        }
        let missing = wanted.subtracting(registered.keys).subtracting(unavailable)
        guard !missing.isEmpty else { return }
        installHandlerIfNeeded()
        for action in missing {
            var reference: EventHotKeyRef?
            let hotKeyId = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(UInt32(action.keyCode), UInt32(cmdKey | optionKey), hotKeyId,
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registered[action] = reference
            } else {
                unavailable.insert(action)
                logger.warning("Shortcut Option+Command for \(String(describing: action), privacy: .public) is taken (status \(status, privacy: .public))")
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyId = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
            guard status == noErr, let action = Action(rawValue: hotKeyId.id) else { return status }
            MainActor.assumeIsolated {
                Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            }
            return noErr
        }, 1, &eventType, context, &handler)
    }
}
