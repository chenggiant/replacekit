import ApplicationServices
import Foundation

public struct AXElement: @unchecked Sendable {
    public let rawValue: AXUIElement

    public init(_ rawValue: AXUIElement) {
        self.rawValue = rawValue
    }

    public func copyAttribute(_ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(rawValue, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    public func string(_ attribute: CFString) -> String? {
        copyAttribute(attribute) as? String
    }

    public func elements(_ attribute: CFString) -> [AXElement] {
        guard let values = copyAttribute(attribute) as? [AXUIElement] else {
            return []
        }
        return values.map(AXElement.init)
    }

    public var children: [AXElement] {
        elements(kAXChildrenAttribute as CFString)
    }

    public var role: String? {
        string(kAXRoleAttribute as CFString)
    }

    public var subrole: String? {
        string(kAXSubroleAttribute as CFString)
    }

    public var title: String? {
        string(kAXTitleAttribute as CFString)
    }

    public var label: String? {
        string(kAXDescriptionAttribute as CFString)
    }

    public var value: String? {
        string(kAXValueAttribute as CFString)
    }

    public var isEnabled: Bool {
        (copyAttribute(kAXEnabledAttribute as CFString) as? Bool) ?? false
    }

    public var position: CGPoint? {
        point(kAXPositionAttribute as CFString)
    }

    public var size: CGSize? {
        size(kAXSizeAttribute as CFString)
    }

    public var descendants: [AXElement] {
        children + children.flatMap(\.descendants)
    }

    public func press() throws {
        let error = AXUIElementPerformAction(rawValue, kAXPressAction as CFString)
        guard error == .success else {
            throw AXElementError.actionFailed(error.rawValue)
        }
    }

    public func setStringValue(_ value: String) throws {
        try set(attribute: kAXValueAttribute as CFString, value: value as CFString)
    }

    public func setPosition(_ point: CGPoint) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw AXElementError.eventCreationFailed
        }
        try set(attribute: kAXPositionAttribute as CFString, value: value)
    }

    public func select() throws {
        try set(attribute: kAXSelectedAttribute as CFString, value: kCFBooleanTrue)
    }

    public func focus() throws {
        try set(attribute: kAXFocusedAttribute as CFString, value: kCFBooleanTrue)
    }

    public static func pressTab() throws {
        try pressKey(virtualKey: 48)
    }

    public static func nudgeTextValidation() throws {
        try pressKey(virtualKey: 49)
        try pressKey(virtualKey: 51)
    }

    private static func pressKey(
        virtualKey: CGKeyCode,
        flags: CGEventFlags = []
    ) throws {
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else {
            throw AXElementError.eventCreationFailed
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    public func clickAtCenter() throws {
        guard let position, let size else {
            throw AXElementError.missingGeometry
        }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        guard
            let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            throw AXElementError.eventCreationFailed
        }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func set(attribute: CFString, value: CFTypeRef) throws {
        let error = AXUIElementSetAttributeValue(rawValue, attribute, value)
        guard error == .success else {
            throw AXElementError.setFailed(error.rawValue)
        }
    }

    private func point(_ attribute: CFString) -> CGPoint? {
        guard let value = copyAttribute(attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func size(_ attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}

public enum AXElementError: Error {
    case actionFailed(Int32)
    case setFailed(Int32)
    case missingGeometry
    case eventCreationFailed
}
