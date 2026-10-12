@main
struct StreamWindowRecoveryRegression {
    static func main() {
        var stopped = StreamWindowRecoveryState()
        precondition(stopped.beginTeardown())
        precondition(!stopped.beginTeardown(), "Resource teardown must remain idempotent")
        precondition(stopped.stoppedMenuPresentation(menuAlreadyAvailable: false) == .push,
                     "An already-torn-down stopped page must still open its menu")
        precondition(stopped.stoppedMenuPresentation(menuAlreadyAvailable: false) == .activate,
                     "Repeated recovery must activate the singleton, not silently return")
        print("PASS: teardown already completed; stopped-page recovery and repeated taps")

        var pushed = StreamWindowRecoveryState()
        precondition(pushed.beginLiveMenuPresentation())
        precondition(!pushed.beginLiveMenuPresentation())
        precondition(pushed.beginTeardown())
        precondition(pushed.stoppedMenuPresentation(menuAlreadyAvailable: true) == .activate,
                     "Stopping from a pushed menu must not be blocked by the Home guard")
        print("PASS: Home -> menu -> Stop activates existing menu")

        var resumed = StreamWindowRecoveryState()
        precondition(resumed.beginLiveMenuPresentation())
        resumed.didResumeStream()
        precondition(resumed.beginLiveMenuPresentation(), "Resume must re-arm Home")
        resumed.didResumeStream()
        precondition(resumed.beginTeardown())
        precondition(resumed.stoppedMenuPresentation(menuAlreadyAvailable: false) == .push)
        precondition(!resumed.beginLiveMenuPresentation(), "A dead stream cannot be resumed")
        print("PASS: Home -> Resume -> Home -> Resume -> Stop")

        var failed = StreamWindowRecoveryState()
        precondition(failed.stoppedMenuPresentation(menuAlreadyAvailable: false) == .push)
        precondition(failed.beginTeardown())
        precondition(failed.stoppedMenuPresentation(menuAlreadyAvailable: false) == .activate)
        print("PASS: startup failure and recovery/teardown callback ordering")

        precondition(StoppedStreamScene.classic.windowID == "classicStreamingWindow")
        precondition(StoppedStreamScene.realityKitVolume.windowID == "realitykitStreamingWindow")
        precondition(StoppedStreamScene.immersive.windowID == nil)
        print("PASS: classic, volume and immersive destination cleanup")

        var historicalMenu = MainMenuVisibilityState()
        historicalMenu.windowDidAppear()
        for _ in 0..<100 {
            historicalMenu.hideForStream()
            precondition(historicalMenu.hasWindow, "Streaming must not destroy the original menu")
            precondition(!historicalMenu.canAcknowledgeReturn, "An invisible menu cannot close the stream")
            var stream = StreamWindowRecoveryState()
            precondition(stream.beginTeardown())
            precondition(stream.stoppedMenuPresentation(menuAlreadyAvailable: historicalMenu.hasWindow) == .activate,
                         "Return must activate the historical menu, not push a newly placed menu")
            historicalMenu.showForNavigation()
            precondition(historicalMenu.canAcknowledgeReturn)
        }
        print("PASS: 100 stream/return cycles retain the historical menu and acknowledge only when visible")

        historicalMenu.windowDidDisappear()
        precondition(!historicalMenu.canAcknowledgeReturn)
        var intentStream = StreamWindowRecoveryState()
        precondition(intentStream.stoppedMenuPresentation(menuAlreadyAvailable: historicalMenu.hasWindow) == .push)
        print("PASS: explicitly closed menu / intent launch falls back safely")
    }
}
