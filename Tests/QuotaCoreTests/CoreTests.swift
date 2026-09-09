import XCTest
import CoreGraphics
@testable import QuotaCore

final class CoreTests: XCTestCase {
    func testPinToggleAttachesWhenHollowAndDetachesWhenFilled() {
        XCTAssertEqual(AttachmentToggleAction.next(isAttached: false), .attach)
        XCTAssertEqual(AttachmentToggleAction.next(isAttached: true), .detach)
    }

    func testPrefersBucketsAndKeepsDistinctLimits() throws {
        let json = #"{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":13,"windowDurationMins":300,"resetsAt":2000},"secondary":{"usedPercent":6,"windowDurationMins":10080}},"review":{"limitName":"Review","primary":{"usedPercent":20}}},"rateLimitResetCredits":{"availableCount":2}}"#
        let snapshot = try QuotaSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.buckets.map(\.id), ["codex", "review"])
        XCTAssertEqual(snapshot.buckets.first?.primary?.remainingPercent, 87)
        XCTAssertEqual(snapshot.buckets.first?.secondary?.remainingPercent, 94)
        XCTAssertNil(snapshot.buckets.last?.secondary)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
    }

    func testMissingResetCreditsRemainUnknown() throws {
        let snapshot = try QuotaSnapshot.decode(Data(#"{"rateLimits":{"primary":{"usedPercent":10}}}"#.utf8))
        XCTAssertNil(snapshot.availableResetCredits)
    }

    func testLegacyAndMissingWindowsDoNotBecomeZeroQuota() throws {
        let snapshot = try QuotaSnapshot.decode(Data(#"{"rateLimits":{"primary":null,"secondary":{"usedPercent":0}}}"#.utf8))
        XCTAssertEqual(snapshot.buckets.count, 1)
        XCTAssertNil(snapshot.buckets.first?.primary)
        XCTAssertEqual(snapshot.buckets.first?.secondary?.remainingPercent, 100)
        XCTAssertThrowsError(try QuotaSnapshot.decode(Data(#"{"rateLimits":null}"#.utf8)))
        XCTAssertThrowsError(try QuotaSnapshot.decode(Data(#"{"rateLimits":{"primary":null}}"#.utf8)))
    }

    func testPercentBoundsAndResetDeadline() throws {
        let window = try JSONDecoder().decode(QuotaWindow.self, from: Data(#"{"usedPercent":101,"windowDurationMins":300,"resetsAt":2000}"#.utf8))
        XCTAssertEqual(window.remainingPercent, 0)
        XCTAssertEqual(window.title, "5 小时")
        XCTAssertEqual(window.resetText(now: Date(timeIntervalSince1970: 1400)), "10 分钟后重置")
        XCTAssertEqual(window.resetText(now: Date(timeIntervalSince1970: 2001)), "等待额度更新")
        let negative = try JSONDecoder().decode(QuotaWindow.self, from: Data(#"{"usedPercent":-2,"windowDurationMins":10080}"#.utf8))
        XCTAssertEqual(negative.remainingPercent, 100)
        XCTAssertEqual(negative.title, "每周")
    }

    func testFollowHidesForMinimizedOrInactiveTargetWhileAlwaysStaysVisible() {
        XCTAssertFalse(DisplayMode.follow.shouldShow(targetVisible: false, targetActive: true))
        XCTAssertFalse(DisplayMode.follow.shouldShow(targetVisible: true, targetActive: false))
        XCTAssertTrue(DisplayMode.follow.shouldShow(targetVisible: true, targetActive: true))
        XCTAssertTrue(DisplayMode.always.shouldShow(targetVisible: false, targetActive: false))
        XCTAssertTrue(DisplayMode.normal.shouldShow(targetVisible: false, targetActive: false))
    }

    func testFourEdgesSnapAndUnrelatedRectDoesNot() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let examples: [(CGRect, Attachment.Edge)] = [
            (CGRect(x: 910, y: 400, width: 300, height: 300), .right),
            (CGRect(x: -210, y: 400, width: 300, height: 300), .left),
            (CGRect(x: 300, y: 710, width: 300, height: 300), .top),
            (CGRect(x: 300, y: -210, width: 300, height: 300), .bottom)
        ]
        for (rect, edge) in examples { XCTAssertEqual(Attachment.snap(panel: rect, target: target)?.edge, edge) }
        XCTAssertNil(Attachment.snap(panel: CGRect(x: 950, y: 1800, width: 300, height: 300), target: target))
        XCTAssertNil(Attachment.snap(panel: CGRect(x: 1300, y: 400, width: 300, height: 300), target: target))
    }

    func testAttachedPanelFollowsMoveAndFitsNegativeCoordinateMonitor() {
        let a = Attachment(edge: .right, offset: 0)
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let rect = a.frame(target: CGRect(x: -1500, y: 0, width: 800, height: 600), size: CGSize(width: 300, height: 300), screen: screen)
        XCTAssertEqual(rect, CGRect(x: -692, y: 300, width: 300, height: 300))
        let atEdge = a.frame(target: CGRect(x: -900, y: 0, width: 890, height: 600), size: CGSize(width: 300, height: 300), screen: screen)
        XCTAssertTrue(screen.contains(atEdge))
        XCTAssertEqual(atEdge.maxY, 600)
    }

    func testScreenFitPreservesSizeAndMovesOffscreenPanelBack() {
        XCTAssertEqual(Attachment.fit(CGRect(x: 1800, y: -100, width: 300, height: 300), in: CGRect(x: 0, y: 0, width: 1920, height: 1080)), CGRect(x: 1620, y: 0, width: 300, height: 300))
    }

    func testExpandingMiniAtBottomRightKeepsWholeCardVisible() {
        let mini = CGRect(x: 1656, y: 0, width: 264, height: 64)
        let result = Attachment.resized(mini, to: CGSize(width: 304, height: 344), screen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(result, CGRect(x: 1616, y: 0, width: 304, height: 344))
    }

    func testFourInteriorEdgesRemainAttachedWhenOutsideDoesNotFit() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = screen
        let cases: [(CGRect, Attachment.Edge)] = [
            (CGRect(x: 692, y: 400, width: 300, height: 300), .right),
            (CGRect(x: 8, y: 400, width: 300, height: 300), .left),
            (CGRect(x: 350, y: 492, width: 300, height: 300), .top),
            (CGRect(x: 350, y: 8, width: 300, height: 300), .bottom)
        ]
        for (panel, edge) in cases {
            XCTAssertEqual(Attachment.snap(panel: panel, target: target, screen: screen)?.edge, edge)
        }
    }

    func testInteriorPositionDoesNotJumpOutsideWhenThereIsRoom() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let panel = CGRect(x: 592, y: 350, width: 300, height: 300)
        XCTAssertNil(Attachment.snap(panel: panel, target: target, screen: screen))
    }

    func testDetachMovesPanelPastSnapThresholdAndDoesNotImmediatelyReattach() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = screen
        for attachment in [
            Attachment(edge: .right, offset: 16),
            Attachment(edge: .left, offset: 16),
            Attachment(edge: .top, offset: 120),
            Attachment(edge: .bottom, offset: 120)
        ] {
            let attached = attachment.frame(target: target, size: CGSize(width: 300, height: 300), screen: screen)
            let detached = attachment.detachedFrame(from: attached, target: target, screen: screen)
            XCTAssertNil(Attachment.snap(panel: detached, target: target, screen: screen), "\(attachment.edge) should stay detached")
        }
    }
}
