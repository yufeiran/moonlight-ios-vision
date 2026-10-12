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
    static let stream = CGSize(width: 960, height: 540)

    /// Window points only; never changes the negotiated video resolution.
    static func compactStreamSize(width: Int32, height: Int32, saved: CGSize? = nil) -> CGSize {
        let ratio = width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 16.0 / 9.0
        let savedWidth = saved?.width ?? stream.width
        let widthLimit = savedWidth.isFinite && savedWidth > 0 ? min(savedWidth, stream.width) : stream.width
        let desiredWidth = min(widthLimit, 720 * ratio)
        return CGSize(width: desiredWidth, height: desiredWidth / ratio)
    }
}
