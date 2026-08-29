@testable import AppBundle
import XCTest

final class BackgroundNativeTabTest: XCTestCase {
    private let tabFrame = Rect(topLeftX: 6143, topLeftY: 1676, width: 1536, height: 849)
    private let ownFrame = Rect(topLeftX: 0, topLeftY: 0, width: 1536, height: 849)
    private let none = Set<UInt32>()

    func testUnselectedTabIsDetected() {
        // Finder with two tabs: both windows are alive and stacked, only the selected one is an AXWindow
        let ids = backgroundNativeTabIds(
            frames: [2976: tabFrame, 2970: tabFrame],
            axWindowIds: [2976],
            tabCounts: [2976: 2],
        )
        assertEquals(ids, [2970])
    }

    func testEveryTabButTheSelectedOneIsDetected() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: tabFrame, 3: tabFrame],
            axWindowIds: [2],
            tabCounts: [2: 3],
        )
        assertEquals(ids, [1, 3])
    }

    func testWindowsPresentInAxWindowsAreKept() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: ownFrame],
            axWindowIds: [1, 2],
            tabCounts: [1: 2, 2: 0],
        )
        assertEquals(ids, none)
    }

    /// Windows on inactive macOS Spaces are absent from AXWindows too, so absence alone must not
    /// be enough to drop a window
    func testAbsentWindowWithItsOwnFrameIsKept() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: ownFrame],
            axWindowIds: [1],
            tabCounts: [1: 2],
        )
        assertEquals(ids, none)
    }

    /// The case the tab bar guard exists for: two windows of one app stacked at one frame, one of
    /// them on an inactive macOS Space. Without a tab bar there is nothing hiding behind anything
    func testStackedWindowIsKeptWhenThereIsNoTabBar() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: tabFrame],
            axWindowIds: [1],
            tabCounts: [1: 0],
        )
        assertEquals(ids, none)
    }

    func testSingleTabHidesNothing() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: tabFrame],
            axWindowIds: [1],
            tabCounts: [1: 1],
        )
        assertEquals(ids, none)
    }

    /// Three stacked windows but only two tabs: one of them is not a tab, and guessing which would
    /// risk dropping a real window
    func testDropsNoMoreWindowsThanTheTabBarAccountsFor() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: tabFrame, 3: tabFrame],
            axWindowIds: [1],
            tabCounts: [1: 2],
        )
        assertEquals(ids.count, 1)
    }

    func testNothingIsDroppedWhenNoWindowIsSelected() {
        let ids = backgroundNativeTabIds(frames: [1: tabFrame, 2: tabFrame], axWindowIds: [], tabCounts: [:])
        assertEquals(ids, none)
    }

    func testFrameMustMatchExactly() {
        let almost = Rect(topLeftX: 6143, topLeftY: 1676, width: 1536, height: 850)
        let ids = backgroundNativeTabIds(frames: [1: tabFrame, 2: almost], axWindowIds: [1], tabCounts: [1: 2])
        assertEquals(ids, none)
    }

    /// Two separate tabbed windows of one app must not consume each other's tabs
    func testTwoTabbedWindowsAreHandledIndependently() {
        let ids = backgroundNativeTabIds(
            frames: [1: tabFrame, 2: tabFrame, 3: ownFrame, 4: ownFrame],
            axWindowIds: [1, 3],
            tabCounts: [1: 2, 3: 2],
        )
        assertEquals(ids, [2, 4])
    }
}
