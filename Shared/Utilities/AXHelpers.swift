//
//  AXHelpers.swift
//  Shared
//

import ApplicationServices
import Cocoa

enum AXHelpers {
    struct Role: RawRepresentable, Equatable, Hashable {
        let rawValue: String
        static let menuBar = Role(rawValue: kAXMenuBarRole as String)
    }

    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync {
            if prompt {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let options = [key: true] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            }
            return AXIsProcessTrusted()
        }
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        queue.sync {
            let systemWide = AXUIElementCreateSystemWide()
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success else {
                return nil
            }
            return element
        }
    }

    static func application(for runningApp: NSRunningApplication) -> AXUIElement? {
        queue.sync {
            AXUIElementCreateApplication(runningApp.processIdentifier)
        }
    }

    static func extrasMenuBar(for app: AXUIElement) -> AXUIElement? {
        queue.sync {
            copyElementAttribute(app, attribute: "AXExtrasMenuBar")
        }
    }

    static func children(for element: AXUIElement) -> [AXUIElement] {
        queue.sync {
            guard let value = copyAttributeValue(element, attribute: kAXChildrenAttribute) else {
                return []
            }
            return value as? [AXUIElement] ?? []
        }
    }

    static func isEnabled(_ element: AXUIElement) -> Bool {
        queue.sync {
            guard let number = copyAttributeValue(element, attribute: kAXEnabledAttribute) as? NSNumber else {
                return false
            }
            return number.boolValue
        }
    }

    static func frame(for element: AXUIElement) -> CGRect? {
        queue.sync {
            if
                let frameValue = copyAttributeValue(element, attribute: "AXFrame"),
                CFGetTypeID(frameValue) == AXValueGetTypeID()
            {
                var rect = CGRect.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(frameValue as! AXValue, .cgRect, &rect) {
                    return rect
                }
            }
            guard
                let positionValue = copyAttributeValue(element, attribute: kAXPositionAttribute),
                CFGetTypeID(positionValue) == AXValueGetTypeID(),
                let sizeValue = copyAttributeValue(element, attribute: kAXSizeAttribute),
                CFGetTypeID(sizeValue) == AXValueGetTypeID()
            else {
                return nil
            }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard
                // swiftlint:disable:next force_cast
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                // swiftlint:disable:next force_cast
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            else {
                return nil
            }
            return CGRect(origin: position, size: size)
        }
    }

    static func role(for element: AXUIElement) -> Role? {
        queue.sync {
            guard let raw = copyAttributeValue(element, attribute: kAXRoleAttribute) as? String else {
                return nil
            }
            return Role(rawValue: raw)
        }
    }

    /// Returns the menu bar that holds the application menus, found at the
    /// given point before macOS 27.
    ///
    /// On macOS 27 the element at a display's origin is MenuBarAgent's window,
    /// so the menu bar comes from the application that owns it. MacBar's own menus
    /// are skipped there: asking our own process from the main thread would wait
    /// for the main thread itself.
    static func applicationMenuBar(at point: CGPoint) -> AXUIElement? {
        if #available(macOS 27.0, *) {
            guard
                let owner = NSWorkspace.shared.menuBarOwningApplication,
                owner.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let app = application(for: owner)
            else {
                return nil
            }
            return queue.sync {
                copyElementAttribute(app, attribute: kAXMenuBarAttribute)
            }
        }
        guard let element = element(at: point), role(for: element) == .menuBar else {
            return nil
        }
        return element
    }

    private static func copyAttributeValue(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard
            let value = copyAttributeValue(element, attribute: attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }
}
