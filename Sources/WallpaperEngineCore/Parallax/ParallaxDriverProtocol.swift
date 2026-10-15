import Foundation
import simd

/// Protocol for position tracking drivers that produce normalized 2D parallax offsets.
public protocol ParallaxTrackingDriver: AnyObject, Sendable {
    /// Callback triggered when a new smoothed parallax offset is computed.
    /// Values are normalized to `[-1.0, 1.0]` for both x and y axes.
    var onOffsetUpdate: (@Sendable (SIMD2<Float>) -> Void)? { get set }

    /// The current smoothed offset vector.
    var currentOffset: SIMD2<Float> { get }

    /// Starts tracking input.
    func start()

    /// Stops tracking input and releases resources.
    func stop()
}
