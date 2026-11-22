import Testing
import ZeigCore

/// The promise: if the window isn't up, a press brings it up.
@Suite struct PictureInPictureStateTests {
    @Test func aPressStartsAndOnlyIOSMakesItOn() {
        var state = PictureInPictureState()
        #expect(!state.showsOn)
        #expect(state.press() == .start)
        #expect(state.phase == .starting(attempt: 1))
        #expect(state.showsOn, "the switch shows the request right away")
        state.systemStarted()
        #expect(state.phase == .on)
    }

    @Test func aPressWhileStartingTriesAgainInsteadOfTurningOff() {
        var state = PictureInPictureState()
        _ = state.press()
        // iOS said nothing: to the user, nothing happened.
        #expect(state.press() == .restart)
        #expect(state.phase == .starting(attempt: 1))
        #expect(state.showsOn)
    }

    @Test func aPressAfterClosingBringsItBack() {
        var state = PictureInPictureState()
        _ = state.press()
        state.systemStarted()
        #expect(state.press() == .stop)
        #expect(!state.showsOn)
        #expect(state.systemStopped() == .finish)
        #expect(state.phase == .off)
        #expect(state.press() == .start)
    }

    @Test func aPressWhileClosingRestartsOnceTheWindowIsGone() {
        var state = PictureInPictureState()
        _ = state.press()
        state.systemStarted()
        _ = state.press()
        #expect(state.press() == .none, "the window is still on its way out")
        #expect(state.showsOn)
        #expect(state.systemStopped() == .start)
        #expect(state.phase == .starting(attempt: 1))
    }

    @Test func closingFromTheWindowItselfTurnsItOff() {
        var state = PictureInPictureState()
        _ = state.press()
        state.systemStarted()
        #expect(state.systemStopped() == .finish)
        #expect(!state.showsOn)
        #expect(state.press() == .start)
    }

    @Test func aFailedStartRetriesThenLetsTheNextPressStartClean() {
        var state = PictureInPictureState()
        _ = state.press()
        #expect(state.attemptFailed() == .restart)
        #expect(state.phase == .starting(attempt: 2))
        #expect(state.attemptFailed() == .finish)
        #expect(state.phase == .off)
        #expect(state.failed)
        #expect(!state.showsOn, "never left on with no window")
        #expect(state.press() == .start)
        #expect(!state.failed)
    }

    @Test func theEndOfAnEarlierWindowDoesntCancelANewStart() {
        var state = PictureInPictureState()
        _ = state.press()
        #expect(state.systemStopped() == .none)
        #expect(state.phase == .starting(attempt: 1))
    }

    @Test func aLateFailureAfterStartingIsIgnored() {
        var state = PictureInPictureState()
        _ = state.press()
        state.systemStarted()
        #expect(state.attemptFailed() == .none)
        #expect(state.phase == .on)
    }

    @Test func turningOffNeverRestarts() {
        var starting = PictureInPictureState()
        _ = starting.press()
        #expect(starting.turnOff() == .finish)
        #expect(starting.phase == .off)

        var closing = PictureInPictureState()
        _ = closing.press()
        closing.systemStarted()
        _ = closing.press()
        _ = closing.press()
        #expect(closing.turnOff() == .none)
        #expect(closing.systemStopped() == .finish)
        #expect(closing.phase == .off)

        var off = PictureInPictureState()
        #expect(off.turnOff() == .none)
    }
}
