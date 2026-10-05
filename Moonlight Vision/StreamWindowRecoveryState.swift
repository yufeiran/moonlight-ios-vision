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

    mutating func stoppedMenuPresentation(menuAlreadyPushed: Bool) -> MenuPresentation {
        let activateExisting = menuAlreadyPushed || isMenuPushed || isReturningAfterStop
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
