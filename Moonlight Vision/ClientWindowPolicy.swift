import Foundation
import SwiftUI

/// Keep the value alive while SwiftUI dismantles a child after its optional
/// scene/selection has been cleared. Binding(optional) instead force-unwraps
/// the source again during that final update and can trap on nil.
func retainedSceneBinding<Value>(snapshot: Value) -> Binding<Value> {
    .constant(snapshot)
}

enum ClientWindowSizing {
    static let main = CGSize(width: 900, height: 600)
    static let stream = CGSize(width: 1200, height: 675)

    /// Enlarge only build 30's default-size history once, not a user's custom size.
    static func migratePreviousStreamDefault(in defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: "yuStreamWindowSizeRevision") < 2 else { return }
        if let width = defaults.object(forKey: "uikitWindowWidth") as? Double,
           let height = defaults.object(forKey: "uikitWindowHeight") as? Double,
           width.isFinite, height.isFinite, width > 0, height > 0,
           abs(width - 960) < 2 || (abs(height - 720) < 2 && width <= 960) {
            defaults.set(width * 1.25, forKey: "uikitWindowWidth")
            defaults.set(height * 1.25, forKey: "uikitWindowHeight")
        }
        defaults.set(2, forKey: "yuStreamWindowSizeRevision")
    }

    /// Window points only; never changes the negotiated video resolution.
    static func compactStreamSize(width: Int32, height: Int32, saved: CGSize? = nil) -> CGSize {
        let ratio = width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 16.0 / 9.0
        let savedWidth = saved?.width ?? stream.width
        let widthLimit = savedWidth.isFinite && savedWidth > 0 ? min(savedWidth, stream.width) : stream.width
        let desiredWidth = min(widthLimit, 900 * ratio)
        return CGSize(width: desiredWidth, height: desiredWidth / ratio)
    }
}
