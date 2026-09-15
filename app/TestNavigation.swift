import Foundation

// Double precision and multiplicative zoom avoid arbitrary travel/zoom limits.
// Reject only values beyond representable floating-point range.
struct TestNavigation {
    static let initialScale = 2.1
    var scale = initialScale
    var pan = SIMD2<Double>.zero
    mutating func advance(horizontal: Double, vertical: Double, zoom: Double, seconds: Double) {
        let nextScale = scale * exp(zoom * seconds * 1.8)
        if nextScale.isFinite && nextScale > 0 {scale = nextScale}
        let nextPan = pan + SIMD2(horizontal, vertical) * (scale * seconds * 1.8)
        if nextPan.x.isFinite && nextPan.y.isFinite {pan = nextPan}
    }
    mutating func reset() {self = Self()}
}
