import XCTest
@testable import AIMonCore

final class WatcherConfigTests: XCTestCase {
    func test_default_isValid() {
        let c = WatcherConfig.default
        XCTAssertTrue(WatcherConfig.isValid(liveWindow: c.liveWindow, staleTimeout: c.staleTimeout,
                                            pollInterval: c.pollInterval, probeTimeout: c.probeTimeout,
                                            transcriptReadBytes: c.transcriptReadBytes))
    }

    func test_default_values() {
        let c = WatcherConfig.default
        XCTAssertEqual(c.pollInterval, 2)
        XCTAssertEqual(c.liveWindow, 30)
        XCTAssertEqual(c.staleTimeout, 90)
        XCTAssertEqual(c.probeTimeout, 3)
    }

    func test_isValid_rejectsLiveWindowNotLessThanStale() {
        XCTAssertFalse(WatcherConfig.isValid(liveWindow: 90, staleTimeout: 90, pollInterval: 2,
                                             probeTimeout: 3, transcriptReadBytes: 65536))
    }

    func test_isValid_rejectsNonPositiveIntervals() {
        XCTAssertFalse(WatcherConfig.isValid(liveWindow: 0, staleTimeout: 90, pollInterval: 2,
                                             probeTimeout: 3, transcriptReadBytes: 65536))
        XCTAssertFalse(WatcherConfig.isValid(liveWindow: 30, staleTimeout: 90, pollInterval: 0,
                                             probeTimeout: 3, transcriptReadBytes: 65536))
        XCTAssertFalse(WatcherConfig.isValid(liveWindow: 30, staleTimeout: 90, pollInterval: 2,
                                             probeTimeout: 0, transcriptReadBytes: 65536))
    }

    func test_isValid_rejectsTinyReadBudget() {
        XCTAssertFalse(WatcherConfig.isValid(liveWindow: 30, staleTimeout: 90, pollInterval: 2,
                                             probeTimeout: 3, transcriptReadBytes: 100))
    }

    func test_renderConfig_defaults() {
        XCTAssertEqual(RenderConfig.default.pixelScale, 16)
        XCTAssertEqual(RenderConfig.default.cascadeStep, 40)
    }
}
