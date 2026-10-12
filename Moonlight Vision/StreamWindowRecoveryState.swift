// Resource teardown and window navigation have different lifetimes. In particular,
// a stopped/error view must still be able to return after teardown has already run.
struct StreamWindowRecoveryState {
    enum MenuPresentation {
        case push
        case activate
    }

    private(set) var hasPerformedTeardown = false
    private(set) var isMenuPushed = false
    private(set) var isReturningAfterStop = false

    mutating func beginTeardown() -> Bool {
        guard !hasPerformedTeardown else { return false }
        hasPerformedTeardown = true
        return true
    }

    mutating func beginLiveMenuPresentation() -> Bool {
        guard !hasPerformedTeardown, !isMenuPushed, !isReturningAfterStop else { return false }
        isMenuPushed = true
        return true
    }

    mutating func stoppedMenuPresentation(menuAlreadyAvailable: Bool) -> MenuPresentation {
        let activateExisting = menuAlreadyAvailable || isMenuPushed || isReturningAfterStop
        isReturningAfterStop = true
        isMenuPushed = false
        // Repeated recovery taps can bring the singleton menu forward, rather than
        // being permanently swallowed by an old "returning" flag.
        return activateExisting ? .activate : .push
    }

    mutating func didResumeStream() {
        isMenuPushed = false
    }
}

// Preserve the actual system window instead of attempting to serialize a pose
// that visionOS does not expose to ordinary windows. Hiding content keeps its
// layout, position and user-selected tilt intact within the current session.
struct MainMenuVisibilityState: Equatable {
    private(set) var hasWindow = false
    private(set) var isHiddenForStream = false

    var canAcknowledgeReturn: Bool { hasWindow && !isHiddenForStream }

    mutating func windowDidAppear() { hasWindow = true }
    mutating func windowDidDisappear() { hasWindow = false }
    mutating func hideForStream() { isHiddenForStream = true }
    mutating func showForNavigation() { isHiddenForStream = false }
}

enum StoppedStreamScene: Equatable {
    case classic
    case realityKitVolume
    case immersive

    var windowID: String? {
        switch self {
        case .classic: return "classicStreamingWindow"
        case .realityKitVolume: return "realitykitStreamingWindow"
        case .immersive: return nil
        }
    }
}
