//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permission State

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var cachedPermissionResult: Bool?
    nonisolated(unsafe) private static var captureAccessDeclined = false

    /// Records that screen recording access was declined by the user or system
    /// during the current session so background capture paths stop prompting.
    static func markCapturePermissionDeclined() {
        stateLock.lock()
        captureAccessDeclined = true
        cachedPermissionResult = false
        stateLock.unlock()
    }

    /// Clears the cached permission status and any session decline suppression.
    static func resetCapturePermissionState() {
        stateLock.lock()
        captureAccessDeclined = false
        cachedPermissionResult = nil
        stateLock.unlock()
    }

    private static func isCaptureAccessDeclined() -> Bool {
        stateLock.lock()
        let declined = captureAccessDeclined
        stateLock.unlock()
        return declined
    }

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions without triggering a system prompt.
    static func checkPermissions() -> Bool {
        if isCaptureAccessDeclined() {
            return false
        }
        if #available(macOS 26.0, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            return hasOtherProcessWindowTitle()
        }
        for windowID in Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace]) {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            return window.title != nil
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value,
        // but we can use it as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    /// Returns whether another non-system process exposes a window title via the
    /// Window Server, which only succeeds once screen capture access is granted
    /// and never triggers a permission dialog.
    private static func hasOtherProcessWindowTitle() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let normalLayer = Int(CGWindowLevelForKey(.normalWindow))
        let excludedOwners: Set<String> = ["Window Server", "WindowManager", "Dock"]
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return false
        }
        for info in windowList {
            guard
                let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                ownerPID != ownPID,
                let layer = info[kCGWindowLayer] as? Int,
                layer == normalLayer,
                let title = info[kCGWindowName] as? String,
                !title.isEmpty
            else {
                continue
            }
            if let ownerName = info[kCGWindowOwnerName] as? String, excludedOwners.contains(ownerName) {
                continue
            }
            return true
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        stateLock.lock()
        if captureAccessDeclined {
            stateLock.unlock()
            return false
        }
        if !reset, let result = cachedPermissionResult {
            stateLock.unlock()
            return result
        }
        stateLock.unlock()

        let result = checkPermissions()

        stateLock.lock()
        if captureAccessDeclined {
            stateLock.unlock()
            return false
        }
        cachedPermissionResult = result
        stateLock.unlock()
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        resetCapturePermissionState()
        guard !checkPermissions() else {
            return
        }
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard
            cachedCheckPermissions(),
            let array = Bridging.createCGWindowArray(with: windowIDs)
        else {
            return nil
        }
        let bounds = screenBounds ?? .null
        // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
        // items, so we unfortunately have to use the deprecated CGWindowList API.
        return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option)
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}
