@main
struct StreamWindowRecoveryRegression {
    static func main() {
        var stopped = StreamWindowRecoveryState()
        precondition(stopped.beginTeardown())
        precondition(!stopped.beginTeardown(), "Resource teardown must remain idempotent")
        precondition(stopped.stoppedMenuPresentation(menuAlreadyPushed: false) == .push,
                     "An already-torn-down stopped page must still open its menu")
        precondition(stopped.stoppedMenuPresentation(menuAlreadyPushed: false) == .activate,
                     "Repeated recovery must activate the singleton, not silently return")
        print("PASS: teardown already completed; stopped-page recovery and repeated taps")

        var pushed = StreamWindowRecoveryState()
        precondition(pushed.beginLiveMenuPresentation())
        precondition(!pushed.beginLiveMenuPresentation())
        precondition(pushed.beginTeardown())
        precondition(pushed.stoppedMenuPresentation(menuAlreadyPushed: true) == .activate,
                     "Stopping from a pushed menu must not be blocked by the Home guard")
        print("PASS: Home -> menu -> Stop activates existing menu")

        var resumed = StreamWindowRecoveryState()
        precondition(resumed.beginLiveMenuPresentation())
        resumed.didResumeStream()
        precondition(resumed.beginLiveMenuPresentation(), "Resume must re-arm Home")
        resumed.didResumeStream()
        precondition(resumed.beginTeardown())
        precondition(resumed.stoppedMenuPresentation(menuAlreadyPushed: false) == .push)
        precondition(!resumed.beginLiveMenuPresentation(), "A dead stream cannot be resumed")
        print("PASS: Home -> Resume -> Home -> Resume -> Stop")

        var failed = StreamWindowRecoveryState()
        precondition(failed.stoppedMenuPresentation(menuAlreadyPushed: false) == .push)
        precondition(failed.beginTeardown())
        precondition(failed.stoppedMenuPresentation(menuAlreadyPushed: false) == .activate)
        print("PASS: startup failure and recovery/teardown callback ordering")

        precondition(StoppedStreamScene.classic.windowID == "classicStreamingWindow")
        precondition(StoppedStreamScene.realityKitVolume.windowID == "realitykitStreamingWindow")
        precondition(StoppedStreamScene.immersive.windowID == nil)
        print("PASS: classic, volume and immersive destination cleanup")
    }
}
