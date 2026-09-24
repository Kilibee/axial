import AppKit
import SceneKit

@_silgen_name("AxialTestInput") func testInput(_ value: Double)

@main enum SceneTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let renderer = TestRenderer()
        var profile = Profile()
        renderer.configure(device: 1, profile: profile)
        let view = TestSceneView();view.scene = renderer.scene;view.motionSource = renderer;view.delegate = renderer
        precondition(!renderer.needsFrames)
        testInput(100);precondition(renderer.needsFrames)
        renderer.renderer(view, updateAtTime: 1)
        renderer.renderer(view, updateAtTime: 1.01)
        let moved = renderer.object.simdTransform
        precondition(moved != matrix_identity_float4x4)
        testInput(0);renderer.renderer(view, updateAtTime: 1.02)
        precondition(!renderer.needsFrames)
        renderer.renderer(view, updateAtTime: 20)
        precondition(renderer.object.simdTransform == moved)
        testInput(100);renderer.renderer(view, updateAtTime: 21)
        precondition(renderer.object.simdTransform == moved, "Resuming must not integrate time spent idle")
        profile.translation = false;profile.rotation = false
        renderer.configure(device: 1, profile: profile);precondition(!renderer.needsFrames)
        profile = Profile();profile.deadzone = Array(repeating: 150, count: 6)
        renderer.configure(device: 1, profile: profile);precondition(!renderer.needsFrames)
        profile = Profile();renderer.configure(device: 1, profile: profile)
        testInput(100);precondition(renderer.needsFrames)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        precondition(!renderer.needsFrames, "Stale input must stop rendering")
        renderer.reset();precondition(renderer.needsFrames)
        renderer.renderer(view, updateAtTime: 22)
        precondition(renderer.object.simdTransform == matrix_identity_float4x4)
        precondition(!renderer.needsFrames)
        renderer.configure(device: 2, profile: profile)
        testInput(100);precondition(!renderer.needsFrames, "Other devices must not wake the scene")
        view.updateRendering();precondition(!view.isPlaying && !view.rendersContinuously, "Detached views must stop")
        print("PASS: movement, stop, resume, disabled axes, dead zone, stale input, reset and device selection")
    }
}
