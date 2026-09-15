import Foundation
@main struct NavigationChecks {
    static func main() {
        var state = TestNavigation()
        for _ in 0..<1200 {state.advance(horizontal: 1, vertical: -1, zoom: 0, seconds: 1.0 / 120)}
        precondition(state.pan.x > 30 && state.pan.y < -30, "Panning stopped at the old scene boundary")
        state.reset()
        for _ in 0..<2400 {state.advance(horizontal: 0, vertical: 0, zoom: -1, seconds: 1.0 / 120)}
        precondition(state.scale < 1e-12, "Zoom hit a fixed minimum")
        for _ in 0..<4800 {state.advance(horizontal: 0, vertical: 0, zoom: 1, seconds: 1.0 / 120)}
        precondition(state.scale > 1e12, "Zoom hit a fixed maximum")
        let before = state.scale
        state.advance(horizontal: 0, vertical: 0, zoom: 0, seconds: 1)
        precondition(state.scale == before && state.pan == .zero, "Neutral input drifted")
        state.reset();precondition(state.scale == TestNavigation.initialScale && state.pan == .zero)
        print("Unbounded pan/zoom, neutral input and reset checks passed")
    }
}
