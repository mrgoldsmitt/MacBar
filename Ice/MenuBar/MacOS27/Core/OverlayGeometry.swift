//
//  OverlayGeometry.swift
//  MacBar
//

import CoreGraphics

/// Pure frame calculations for menu bar overlay panels.
enum OverlayGeometry {
    /// Computes the AppKit frame for a menu bar overlay panel on `screenFrame`,
    /// returning `nil` if any input dimension is non-positive or the resulting
    /// frame would spill outside `screenFrame`.
    static func overlayFrame(
        for screenFrame: CGRect,
        menuBarFrame: CGRect,
        shadowMargin: CGFloat = 5
    ) -> CGRect? {
        guard
            screenFrame.width > 0,
            screenFrame.height > 0,
            menuBarFrame.width > 0,
            menuBarFrame.height > 0
        else {
            return nil
        }

        let frame = CGRect(
            x: screenFrame.minX,
            y: (screenFrame.maxY - menuBarFrame.height) - shadowMargin,
            width: screenFrame.width,
            height: menuBarFrame.height + shadowMargin
        )

        guard screenFrame.contains(frame) else {
            return nil
        }

        return frame
    }
}
