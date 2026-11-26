import Testing
@testable import StasisCore

@Suite struct PausedBadgeTests {
    @Test func noBadgeWhenNothingIsPaused() {
        #expect(PausedBadge.text(forPausedCount: 0) == nil)
    }

    @Test func showsTheCount() {
        #expect(PausedBadge.text(forPausedCount: 1) == "1")
        #expect(PausedBadge.text(forPausedCount: 42) == "42")
        #expect(PausedBadge.text(forPausedCount: 99) == "99")
    }

    @Test func capsLargeCountsSoTheBadgeStaysSmall() {
        #expect(PausedBadge.text(forPausedCount: 100) == "99+")
    }
}
