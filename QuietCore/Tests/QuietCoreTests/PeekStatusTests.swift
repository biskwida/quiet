import Foundation
import Testing
@testable import QuietCore

@Suite("Peek status reported by the page")
struct PeekStatusTests {
    @Test func openPeekIsPeeking() {
        let status = PeekStatus(pageMessage: ["peek": "active", "held": 0])
        #expect(status == .peeking(held: 0))
        #expect(status.isPeeking)
    }

    @Test func armedCountsAsPeekingSoTheBannerShowsAtOnce() {
        #expect(PeekStatus(pageMessage: ["peek": "armed", "held": 0]) == .peeking(held: 0))
    }

    @Test func carriesHowManySeenRequestsWereHeld() {
        #expect(PeekStatus(pageMessage: ["peek": "active", "held": 2]) == .peeking(held: 2))
    }

    @Test func offIsNotPeeking() {
        let status = PeekStatus(pageMessage: ["peek": "off", "held": 0])
        #expect(status == .off)
        #expect(!status.isPeeking)
    }

    @Test func missingCountIsZero() {
        #expect(PeekStatus(pageMessage: ["peek": "active"]) == .peeking(held: 0))
    }

    @Test func anythingUnrecognisedIsOff() {
        #expect(PeekStatus(pageMessage: "active") == .off)
        #expect(PeekStatus(pageMessage: ["peek": "something else"]) == .off)
        #expect(PeekStatus(pageMessage: ["held": 3]) == .off)
        #expect(PeekStatus(pageMessage: NSNull()) == .off)
    }

    @Test func confirmedOnlyOnceSomethingWasHeld() {
        #expect(!PeekStatus.peeking(held: 0).seenWasHeld)
        #expect(PeekStatus.peeking(held: 1).seenWasHeld)
        #expect(!PeekStatus.off.seenWasHeld)
    }
}
