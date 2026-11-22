import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("OverlayGeometry")
struct OverlayGeometryTests {
    @Test("Computes overlay frame aligned to top of built-in screen with 5pt shadow margin")
    func computesBuiltInDisplayFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 37)

        let result = OverlayGeometry.overlayFrame(for: screen, menuBarFrame: menuBar, shadowMargin: 5)
        #expect(result == CGRect(x: 0, y: 940, width: 1512, height: 42))
    }

    @Test("Computes overlay frame cleanly on secondary display with negative coordinates")
    func computesExternalDisplayFrame() {
        let screen = CGRect(x: -1920, y: -273, width: 1920, height: 1080)
        let menuBar = CGRect(x: -1920, y: 149, width: 1920, height: 30)

        let result = OverlayGeometry.overlayFrame(for: screen, menuBarFrame: menuBar, shadowMargin: 5)
        #expect(result == CGRect(x: -1920, y: 772, width: 1920, height: 35))
    }

    @Test("Rejects invalid or zero-sized dimensions")
    func rejectsInvalidDimensions() {
        let validScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(OverlayGeometry.overlayFrame(for: .zero, menuBarFrame: CGRect(x: 0, y: 0, width: 1440, height: 24)) == nil)
        #expect(OverlayGeometry.overlayFrame(for: validScreen, menuBarFrame: .zero) == nil)
        #expect(OverlayGeometry.overlayFrame(for: CGRect(x: 0, y: 0, width: 1440, height: 20), menuBarFrame: CGRect(x: 0, y: 0, width: 1440, height: 24)) == nil)
    }
}
