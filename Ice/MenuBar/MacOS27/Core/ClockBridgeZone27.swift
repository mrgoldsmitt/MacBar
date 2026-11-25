//
//  ClockBridgeZone27.swift
//  Ice
//

import CoreGraphics

/// Decides whether a click must be let through to a system item.
///
/// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on
/// the clock (measured on macOS 27.0), so such clicks lift the assertion first.
enum ClockBridgeZone27 {
    /// A child element inside a `MenuBarAgent` menu bar window.
    struct WindowChild: Equatable {
        let identifier: String
        let frame: CGRect
    }

    /// Fallback horizontal reach left of the clock's left edge when no measured span is available.
    static let defaultSystemItemsSpan: CGFloat = 180

    static func shouldBridge(click: CGPoint, systemItemFrames: [CGRect], isConcealing: Bool) -> Bool {
        guard isConcealing else {
            return false
        }
        return systemItemFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(click) }
    }

    /// Measures how far left of the clock's left edge the active display's system items reach.
    static func measuredSystemSpan(systemItemFrames: [CGRect]) -> CGFloat? {
        let drawn = systemItemFrames.filter { $0.width > 1 }
        guard
            let clock = drawn.filter({ $0.width > 80 }).max(by: { $0.width < $1.width }),
            let leftmost = drawn.min(by: { $0.minX < $1.minX })
        else {
            return nil
        }
        return max(clock.minX - leftmost.minX + 12, 0)
    }

    /// Extracts system item frames from a `MenuBarAgent` display window's children.
    ///
    /// Prefers explicit `com.apple.menuextra.*` identifiers when present (so Spotlight or
    /// third-party items between system items are never misclassified and wide layouts are
    /// covered completely), and falls back to the measured/default span left of the clock.
    static func systemItemFrames(
        from children: [WindowChild],
        activeDisplaySpan: CGFloat?,
        nonSystemFrames: [CGRect] = []
    ) -> [CGRect] {
        let identified = children.filter {
            $0.frame.width > 1 && $0.identifier.hasPrefix("com.apple.menuextra.")
        }
        if !identified.isEmpty {
            return identified.map(\.frame)
        }
        guard let clock = children.filter({ $0.frame.width > 80 }).max(by: { $0.frame.width < $1.frame.width }) else {
            return []
        }
        let span = max(activeDisplaySpan ?? defaultSystemItemsSpan, defaultSystemItemsSpan)
        return children.compactMap { child in
            guard child.frame.width > 1, child.frame.minX >= clock.frame.minX - span else {
                return nil
            }
            let center = CGPoint(x: child.frame.midX, y: child.frame.midY)
            if nonSystemFrames.contains(where: { $0.contains(center) }) {
                return nil
            }
            return child.frame
        }
    }

    /// Chooses where to replay a lifted click: the item's live post-lift center if available,
    /// or the original click point otherwise.
    static func clickTarget(originalClick: CGPoint, liveItemFrame: CGRect?) -> CGPoint {
        guard let liveItemFrame, liveItemFrame.width > 1, liveItemFrame.height > 1 else {
            return originalClick
        }
        return CGPoint(x: liveItemFrame.midX, y: liveItemFrame.midY)
    }

    /// Whether a system item should stop attempting `AXPress` after repeated failures.
    ///
    /// Control Center is never permanently ignored because it opens via `AXPress` even under
    /// assessment mode, though it can occasionally take longer on multi-display systems.
    static func shouldTrackPressIgnored(identifier: String, consecutiveFailures: Int) -> Bool {
        if identifier == "com.apple.menuextra.controlcenter" {
            return false
        }
        return consecutiveFailures >= 2
    }
}
