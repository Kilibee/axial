import SwiftUI
import SceneKit
import simd

@_silgen_name("AxialPreviewStart") func previewStart()
@_silgen_name("AxialPreviewStop") func previewStop()
@_silgen_name("AxialPreviewNow") func previewNow() -> UInt64
@_silgen_name("AxialPreviewLostLogs") func previewLostLogs() -> UInt64
@_silgen_name("AxialPreviewRead") func previewRead(_ device: UInt32, _ axes: UnsafeMutablePointer<Double>, _ buttons: UnsafeMutablePointer<UInt32>) -> Bool
@_silgen_name("AxialPreviewPopLog") func previewPopLog(_ timestamp: UnsafeMutablePointer<UInt64>, _ device: UnsafeMutablePointer<UInt32>, _ changed: UnsafeMutablePointer<UInt32>, _ buttons: UnsafeMutablePointer<UInt32>, _ reason: UnsafeMutablePointer<UInt32>, _ identity: UnsafeMutablePointer<UInt32>) -> Bool

struct ButtonEntry: Identifiable {
    let id: UInt64
    let time: Date
    let device: UInt32
    let button: Int
    let pressed: Bool
    let reset: Bool
    let deviceName: String
    let buttonName: String
    init(id: UInt64, time: Date, device: UInt32, button: Int, pressed: Bool, reset: Bool, identity: UInt32) {
        self.id = id;self.time = time;self.device = device;self.button = button
        self.pressed = pressed;self.reset = reset
        let layout = DeviceCatalog.layouts[identity]
        deviceName = layout?.name ?? (identity == 0 ? "Unknown controller" : String(format: "USB controller %04x:%04x", identity >> 16, identity & 0xffff))
        buttonName = layout?.buttonName(slot: button - 1) ?? "Unknown button (\(button))"
    }
    var csvRow: String {
        func quoted(_ text: String) -> String {"\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""}
        return "\(time.ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))),\(device),\(button),\(pressed ? "pressed" : "released"),\(reset ? "reset" : "device"),\(quoted(deviceName)),\(quoted(buttonName))\n"
    }
}

final class TestRenderer: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let object = SCNNode()
    let camera = SCNNode()
    private(set) var modelError: String?
    private let lock = NSLock()
    private let frameLock = NSLock()
    private var gain = SIMD8<Double>(repeating: 1)
    private var deadzone = SIMD8<Double>(repeating: 0)
    private var dominant = false
    private var device: UInt32 = 0
    private var resetRequested = false
    private var lastTime: TimeInterval = 0
    private var navigation = TestNavigation()
    override init() {
        super.init()
        scene.rootNode.addChildNode(object)
        do {
            guard let url = Bundle.main.url(forResource: "ToyCar", withExtension: "scn") else {throw CocoaError(.fileNoSuchFile)}
            object.addChildNode(try TestModel.load(from: url))
        } catch {modelError = "Could not load the toy car: \(error.localizedDescription)"}
        TestModel.studio(in: scene, camera: camera)
    }
    func configure(device: UInt32, profile: Profile) {
        lock.lock();defer {lock.unlock()}
        self.device = device;dominant = profile.dominant
        for i in 0..<6 {
            gain[i] = ((i < 3 && !profile.translation) || (i >= 3 && !profile.rotation)) ? 0 : profile.gain[i] * (profile.invert[i] ? -1 : 1)
            deadzone[i] = profile.deadzone[i]
        }
    }
    func reset() {lock.lock();resetRequested = true;lock.unlock()}
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // A tab transition can briefly leave two SceneKit views using this scene.
        guard frameLock.try() else {return};defer {frameLock.unlock()}
        lock.lock();let device = self.device;let gain = self.gain;let deadzone = self.deadzone;let dominant = self.dominant;let reset = resetRequested;resetRequested = false;lock.unlock()
        if reset {navigation.reset();object.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))}
        let dt = Float(lastTime == 0 ? 0 : min(max(time - lastTime, 0), 0.05));lastTime = time
        var storage = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);var buttons: UInt32 = 0
        withUnsafeMutableBytes(of: &storage) {bytes in
            let axes = bytes.bindMemory(to: Double.self)
            _ = previewRead(device, axes.baseAddress!, &buttons)
            for i in 0..<6 {let x = axes[i];axes[i] = (x < 0 ? -1 : 1) * max(0, abs(x) - deadzone[i]) * gain[i]}
            if dominant, let index = axes.indices.max(by: {abs(axes[$0]) < abs(axes[$1])}) {for i in 0..<6 where i != index {axes[i] = 0}}
            guard reset || axes.contains(where: {$0 != 0}) else {return}
            navigation.advance(horizontal: axes[0] / 350, vertical: -axes[2] / 350, zoom: axes[1] / 350, seconds: Double(dt))
            camera.camera?.orthographicScale = navigation.scale
            let right = camera.simdWorldRight, up = camera.simdWorldUp
            object.position = SCNVector3(CGFloat(Double(right.x) * navigation.pan.x + Double(up.x) * navigation.pan.y), CGFloat(Double(right.y) * navigation.pan.x + Double(up.y) * navigation.pan.y), CGFloat(Double(right.z) * navigation.pan.x + Double(up.z) * navigation.pan.y))
            let rotation = SIMD3<Float>(Float(-axes[3]), Float(axes[5]), Float(-axes[4])) / 350
            let length = simd_length(rotation)
            if length > 0 {object.simdOrientation = simd_normalize(simd_quatf(angle: length * dt * 1.8, axis: rotation / length) * object.simdOrientation)}
        }
    }
}
// Closing settings keeps the menu-bar app alive, so dismantle alone is insufficient.
// Render at full speed only while the test scene can actually be seen.
final class TestSceneView: SCNView {
    private var observers: [NSObjectProtocol] = []
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver);observers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.updateRendering() })
            }
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.setRendering(false) })
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updateRendering() })
            }
        }
        updateRendering()
    }
    private func setRendering(_ enabled: Bool) {rendersContinuously = enabled;isPlaying = enabled}
    func updateRendering() {
        let visible = window.map {$0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)} ?? false
        setRendering(visible && !isHiddenOrHasHiddenAncestor && !NSApp.isHidden)
    }
    override func viewDidHide() {super.viewDidHide();updateRendering()}
    override func viewDidUnhide() {super.viewDidUnhide();updateRendering()}
    deinit {observers.forEach(NotificationCenter.default.removeObserver)}
}
struct TestScene: NSViewRepresentable {
    let renderer: TestRenderer
    let device: UInt32
    let profile: Profile
    func makeNSView(context: Context) -> SCNView {
        let view = TestSceneView();view.scene = renderer.scene;view.pointOfView = renderer.camera;view.delegate = renderer
        view.preferredFramesPerSecond = 120;view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear;return view
    }
    func updateNSView(_ view: SCNView, context: Context) {renderer.configure(device: device, profile: profile)}
    static func dismantleNSView(_ view: SCNView, coordinator: ()) {view.rendersContinuously = false;view.isPlaying = false;view.delegate = nil}
}
struct TestTab: View {
    @EnvironmentObject var model: Model
    var body: some View {
        GeometryReader {space in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Test").font(.title2.bold())
                    Spacer()
                    Button("Reset object") {model.testRenderer.reset()}
                        .help("Restore position, rotation and zoom")
                }
                TestScene(renderer: model.testRenderer, device: UInt32(model.device?.id ?? 0), profile: model.profile)
                    .frame(height: max(190, space.size.height * 0.53))
                    .overlay(alignment: .bottomLeading) {
                        Text("Toy Car · Guido Odendahl & Eric Chadwick · CC0")
                            .font(.caption2).foregroundStyle(.secondary).padding(10)
                    }
                    .panelSurface().clipShape(RoundedRectangle(cornerRadius: 12))
                    .help("Pan and rotate with the cap. Near / far zooms continuously.")
                if let error = model.testRenderer.modelError {Text(error).font(.caption).foregroundStyle(.orange)}
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Button events").font(.headline)
                        Text("\(model.buttonLog.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Button("Export…", action: model.exportButtonLog).help("Export the full session, including events outside the visible history")
                        Button("Clear view", action: model.clearButtonLog)
                    }.padding(12)
                    Divider()
                    ScrollView {
                        if model.buttonLog.isEmpty {
                            Text("Press a controller button to see its events.")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.buttonLog.reversed()) {entry in
                                HStack {
                                    Text(entry.time, format: .dateTime.hour().minute().second(.twoDigits).secondFraction(.fractional(3))).monospacedDigit().frame(width: 110, alignment: .leading)
                                    Text(entry.buttonName).frame(width: 160, alignment: .leading).lineLimit(2)
                                    Text(entry.pressed ? "Pressed" : (entry.reset ? "Released · reset" : "Released"))
                                        .foregroundStyle(entry.pressed ? Color.green : Color.secondary)
                                    Spacer()
                                    Text(entry.deviceName).foregroundStyle(.secondary).lineLimit(2).help(entry.deviceName)
                                }.font(.system(.caption, design: .monospaced)).padding(.horizontal, 12).padding(.vertical, 7)
                                Divider().opacity(0.4)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.lostButtonLogs > 0 {
                        Text("\(model.lostButtonLogs) events exceeded the log buffer.").font(.caption).foregroundStyle(.orange).padding(8)
                    }
                    if let error = model.buttonLogError {Text(error).font(.caption).foregroundStyle(.orange).padding(8)}
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelSurface()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }.frame(width: space.size.width, height: space.size.height, alignment: .top)
        }
    }
}
