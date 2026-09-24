import AppKit
import SceneKit
import Darwin

@_silgen_name("AxialTestInput") func testInput(_ value: Double)

final class FrameCounter: NSObject, SCNSceneRendererDelegate {
    let target: TestRenderer
    private let lock = NSLock()
    private var count = 0
    init(_ target: TestRenderer) {self.target = target}
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        target.renderer(renderer, updateAtTime: time)
        lock.lock();count += 1;lock.unlock()
    }
    var frames: Int {lock.lock();defer {lock.unlock()};return count}
}

@main enum ScenePerformance {
    static func cpu() -> Double {
        var usage = rusage();getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    @MainActor static func main() {
        let app = NSApplication.shared;app.setActivationPolicy(.regular);app.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.level = .floating
        let renderer = TestRenderer();renderer.configure(device: 1, profile: Profile())
        // Command-line executables do not have the packaged scene in Bundle.main.
        if let path = ProcessInfo.processInfo.environment["AXIAL_TEST_SCENE"], let model = try? TestModel.load(from: URL(fileURLWithPath: path)) {renderer.object.addChildNode(model)}
        precondition(!renderer.object.childNodes.isEmpty, "Set AXIAL_TEST_SCENE to the generated ToyCar.scn")
        let view = TestSceneView();view.motionSource = renderer;view.scene = renderer.scene;view.pointOfView = renderer.camera
        let counter = FrameCounter(renderer);view.frameDelegate = counter;view.delegate = counter
        view.preferredFramesPerSecond = 120;view.antialiasingMode = .multisampling4X
        window.contentView = view;window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps: true)
        let seconds = Double(ProcessInfo.processInfo.environment["AXIAL_BENCH_SECONDS"] ?? "5") ?? 5
        func wait(_ seconds: Double) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let event = app.nextEvent(matching: .any, until: min(deadline, Date().addingTimeInterval(0.01)), inMode: .default, dequeue: true) {app.sendEvent(event)}
                app.updateWindows()
            }
        }
        // Let first-use Metal compilation and texture/environment uploads settle.
        wait(10)
        for mode in ["idle", "moving", "stopped", "hidden"] {
            if mode == "hidden" {window.orderOut(nil)}
            testInput(mode == "moving" ? 100 : 0)
            let phaseStart = ProcessInfo.processInfo.systemUptime
            // Oscillate so the car stays inside the viewport for the full run.
            let timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) {_ in
                if mode == "moving" {testInput(100 * cos((ProcessInfo.processInfo.systemUptime - phaseStart) * 2))}
            }
            wait(0.5)
            let start = ProcessInfo.processInfo.systemUptime, initialCPU = cpu(), initialFrames = counter.frames
            wait(seconds)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let frames = counter.frames - initialFrames
            print("{\"mode\":\"\(mode)\",\"seconds\":\(elapsed),\"cpu_percent\":\((cpu() - initialCPU) / elapsed * 100),\"frames\":\(frames),\"visible\":\(window.occlusionState.contains(.visible))}")
            if mode == "moving" {precondition(frames > Int(seconds * 30) && window.occlusionState.contains(.visible), "No sustained visible movement: this is not a valid GUI performance run")}
            if mode != "moving" && ProcessInfo.processInfo.environment["AXIAL_BENCH_BASELINE"] != "1" {
                precondition(frames == 0, "Idle, stopped and hidden scenes must not schedule delegate frames")
            }
            timer.invalidate()
        }
        window.orderOut(nil);view.delegate = nil
    }
}
