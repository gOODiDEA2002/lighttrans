import XCTest
@testable import LightTrans

final class PanelInputHeightMathTests: XCTestCase {
    func testClampedKeeps70To240Range() {
        XCTAssertEqual(PanelInputHeightMath.clamped(10), 70)
        XCTAssertEqual(PanelInputHeightMath.clamped(100), 100)
        XCTAssertEqual(PanelInputHeightMath.clamped(240), 240)
        XCTAssertEqual(PanelInputHeightMath.clamped(500), 240)
    }

    func testDragDownIncreasesHeight() {
        XCTAssertEqual(
            PanelInputHeightMath.heightAfterDrag(baseHeight: 100, deltaY: -30),
            130
        )
    }

    func testDragUpDecreasesHeight() {
        XCTAssertEqual(
            PanelInputHeightMath.heightAfterDrag(baseHeight: 100, deltaY: 20),
            80
        )
    }

    func testResultSectionHeightMatchesV5Budget() {
        XCTAssertEqual(PanelInputHeightMath.resultSectionHeight(inputHeight: 70), 207)
        XCTAssertEqual(PanelInputHeightMath.resultSectionHeight(inputHeight: 100), 192)
        XCTAssertEqual(PanelInputHeightMath.resultSectionHeight(inputHeight: 240), 122)
    }

    func testComposedPanelHeightAlwaysClosesTo600() {
        XCTAssertEqual(PanelInputHeightMath.composedPanelHeight(inputHeight: 70), 600)
        XCTAssertEqual(PanelInputHeightMath.composedPanelHeight(inputHeight: 100), 600)
        XCTAssertEqual(PanelInputHeightMath.composedPanelHeight(inputHeight: 240), 600)
    }
}
