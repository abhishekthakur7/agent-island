import AppKit
import Carbon.HIToolbox
import Foundation
import SessionDomain

enum CurrentMarkedTextState {
    /// NSTextInputContext exposes the active NSTextInputClient used by the
    /// current composition (including CJK IMEs). If no client is active, the
    /// event is treated as unmarked and ordinary text remains untouched.
    @MainActor
    static var hasMarkedText: Bool {
        NSTextInputContext.current?.client.hasMarkedText() ?? false
    }
}

/// Native registration uses Carbon's RegisterEventHotKey API. It installs
/// process-owned hot-key records and a keyboard event handler; it never adds
/// an event tap, asks for Accessibility permission, or synthesizes Host input.
@MainActor
final class CarbonShortcutRegistrationBackend: ShortcutRegistrationBackend {
    private struct Entry {
        let reference: EventHotKeyRef
        let command: ShortcutCommand
        let binding: ShortcutBinding
        let handler: (ShortcutKeyEvent.Phase) -> Void
    }

    private var entries: [ShortcutCommand: Entry] = [:]
    private var eventHandler: EventHandlerRef?

    var readiness: ShortcutRegistrationStatus {
        eventHandler == nil
            ? .unavailable("Carbon event handler could not be installed.")
            : .active
    }

    init() {
        installEventHandler()
    }

    func register(
        command: ShortcutCommand,
        binding: ShortcutBinding,
        handler: @escaping @MainActor @Sendable (ShortcutKeyEvent.Phase) -> Void
    ) -> ShortcutRegistrationBackendResult {
        guard command.isGloballyEligible else {
            return .failed("\(command.identifier) is focused or consequential and cannot be global.")
        }
        guard eventHandler != nil else {
            return .unavailable("Carbon event handler could not be installed.")
        }
        guard entries[command] == nil else {
            return .failed("\(command.identifier) is already registered.")
        }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: Self.identifier(for: command))
        let status = RegisterEventHotKey(
            UInt32(binding.key.rawValue),
            Self.carbonModifiers(binding.modifiers),
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr {
                return .collision("Another application already owns \(binding.renderedLabel()).")
            }
            return .failed("Carbon registration failed (OSStatus \(status)).")
        }
        entries[command] = Entry(reference: reference, command: command, binding: binding, handler: handler)
        return .registered
    }

    func unregister(command: ShortcutCommand) {
        guard let entry = entries.removeValue(forKey: command) else { return }
        _ = UnregisterEventHotKey(entry.reference)
    }

    private func unregisterAll() {
        Array(entries.keys).forEach { unregister(command: $0) }
    }

    private func installEventHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandlerProc,
            types.count,
            &types,
            userData,
            &eventHandler
        )
        if status != noErr { eventHandler = nil }
    }

    private func handle(event: EventRef?, kind: UInt32) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID(signature: 0, id: 0)
        var actualSize = MemoryLayout<EventHotKeyID>.size
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            actualSize,
            &actualSize,
            &identifier
        )
        guard status == noErr, identifier.signature == Self.signature,
              let entry = entries.values.first(where: { Self.identifier(for: $0.command) == identifier.id })
        else { return OSStatus(eventNotHandledErr) }
        let phase: ShortcutKeyEvent.Phase = kind == UInt32(kEventHotKeyReleased) ? .up : .down
        // Carbon can deliver callbacks off the main run loop. Re-enter the
        // main actor before invoking the coordinator's local Overlay closure.
        let handler = entry.handler
        Task { @MainActor in handler(phase) }
        return noErr
    }

    private static let signature: OSType = 0x4154_4C53 // "ATLS"

    private static func identifier(for command: ShortcutCommand) -> UInt32 {
        switch command {
        case .toggleOverlay: 1
        case .nextSession: 2
        case .previousSession: 3
        case .showAll: 4
        case .collapse: 5
        case .inspect: 6
        case .safeAction: 1000
        }
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.function) { value |= UInt32(kEventKeyModifierFnMask) }
        return value
    }

    private static let eventHandlerProc: EventHandlerUPP = { _, event, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let backend = Unmanaged<CarbonShortcutRegistrationBackend>.fromOpaque(userData).takeUnretainedValue()
        guard let event else { return OSStatus(eventNotHandledErr) }
        var kind: UInt32 = 0
        // Event kinds are stable constants and the event reference is only
        // used for dispatch classification here.
        kind = UInt32(GetEventKind(event))
        return backend.handle(event: event, kind: kind)
    }
}

/// Read-only input-source labels. TIS is used only to identify the current
/// source and translate physical positions; bindings remain HID key codes and
/// never match typed characters. CJK/IME sources without a Unicode layout use
/// the safe PhysicalKey fallback labels.
enum NativeShortcutInputSourceResolver {
    static func current() -> ShortcutInputSource {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ShortcutInputSource()
        }
        let identifier = stringProperty(source, key: kTISPropertyInputSourceID)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "unknown"
        let name = stringProperty(source, key: kTISPropertyLocalizedName)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Current keyboard"
        var labels: [UInt16: String] = [:]
        if let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue()
            if let pointer = CFDataGetBytePtr(layoutData) {
                let layout = pointer.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
                for code in UInt16(0)...UInt16(127) {
                    if let label = translate(layout: layout, keyCode: code), !label.isEmpty {
                        labels[code] = label
                    }
                }
            }
        }
        return ShortcutInputSource(identifier: identifier, localizedName: name, keyCodeLabels: labels)
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
        return value as String
    }

    private static func translate(layout: UnsafePointer<UCKeyboardLayout>, keyCode: UInt16) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &actualLength,
            &characters
        )
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: Int(actualLength))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
