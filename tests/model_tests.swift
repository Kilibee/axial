import AppKit

actor MockControl: ServiceRequesting {
    private var texts: [String] = []
    private var pending: [Int: CheckedContinuation<Data, Never>] = [:]
    func request(_ text: String) async -> Data {
        let id = texts.count;texts.append(text)
        return await withCheckedContinuation {pending[id] = $0}
    }
    func requests() -> [String] {texts}
    func respond(_ id: Int, _ json: String) {pending.removeValue(forKey: id)?.resume(returning: Data(json.utf8))}
    func waitForCount(_ count: Int) async {
        for _ in 0..<3000 {
            if texts.count >= count {return}
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Timed out waiting for request \(count), got \(texts)")
    }
}
actor ResponsiveControl: ServiceRequesting {
    private(set) var statusRequests = 0
    func request(_ text: String) async -> Data {
        if text.contains("status") {
            statusRequests += 1
            return Data("{\"devices\":[],\"clients\":1,\"reports\":0,\"overflows\":0,\"rejected\":0,\"foregroundApp\":\"\",\"accessibility\":false,\"mock\":true}".utf8)
        }
        if text.contains("getConfig") {return Data("{\"version\":1,\"profiles\":{\"*\":{}}}".utf8)}
        return Data("{}".utf8)
    }
}
@MainActor final class WeakModel {weak var value: Model?;init(_ value: Model?) {self.value = value}}
@MainActor final class MockLauncher: ServiceLaunching {
    var isRunning = false
    var starts = 0, terminations = 0
    func start() throws {starts += 1;isRunning = true}
    func terminate() {terminations += 1;isRunning = false}
}

@main enum ModelTests {
    @MainActor static func main() async throws {
        // The chart includes native and WebSocket clients, including older status
        // responses which have no web field.
        for (native, web, expected) in [(2, Optional<Int>.none, 2), (2, 0, 2), (2, 3, 5), (0, 3, 3)] {
            let diagnosticsModel = Model(live: false)
            let webStatus = web.map {WebStatus(enabled: true, listening: true, connections: $0, error: "")}
            let status = Status(web: webStatus, devices: [], clients: native, reports: 0, overflows: 0, rejected: 0, foregroundApp: "", accessibility: false, mock: true)
            diagnosticsModel.acceptStatus(try JSONEncoder().encode(status))
            precondition(diagnosticsModel.diagnostics.samples.last?.clients == expected)
            diagnosticsModel.shutdown()
        }
        print("PASS: connected-client chart includes native and WebSocket connections")
        let explorer = DeviceCatalog.layouts[0x046dc627]!
        precondition(explorer.name == "SpaceExplorer" && explorer.buttons.count == 15)
        precondition(explorer.buttonName(slot: 10) == "Fit" && explorer.buttonName(slot: 14) == "2D")
        precondition(DeviceCatalog.layouts[0x046dc626]!.name == "SpaceNavigator")
        precondition(DeviceCatalog.layouts[0x046dc628]!.name == "SpaceNavigator for Notebooks")
        precondition(DeviceCatalog.layouts[0x256fc635]!.buttons.map(\.name) == ["Left", "Right"])
        precondition(DeviceCatalog.layouts[0x256fc652]!.buttons.map(\.name) == ["Left", "Right"])
        precondition(DeviceCatalog.layouts[0x256fc633]!.buttons.count == 31)
        precondition(DeviceCatalog.layouts[0x046dc629]!.buttons.count == 21)
        precondition(DeviceCatalog.layouts.count == 15 && DeviceCatalog.layouts[0xffffffff] == nil)
        precondition(DeviceCatalog.identity(vendor: -1, product: 1) == nil)
        let pro = DeviceCatalog.layouts[0x046dc62b]!
        precondition(pro.buttons.count == 15 && pro.buttons.first!.name == "1" && pro.buttons.first!.id == 12)
        var bindings = Profile();bindings.buttons[12].command = "existing-binding"
        precondition(bindings.buttons[pro.buttons.first!.id].command == "existing-binding")
        let namedPress = ButtonEntry(id: 1, time: Date(timeIntervalSince1970: 0), device: 1, button: 11, pressed: true, reset: false, identity: 0x046dc627)
        let namedRelease = ButtonEntry(id: 2, time: Date(timeIntervalSince1970: 1), device: 1, button: 11, pressed: false, reset: true, identity: 0x046dc627)
        let reusedID = ButtonEntry(id: 3, time: Date(), device: 1, button: 2, pressed: true, reset: false, identity: 0x256fc635)
        precondition(namedPress.deviceName == "SpaceExplorer" && namedPress.buttonName == "Fit")
        precondition(namedRelease.deviceName == "SpaceExplorer" && namedRelease.buttonName == "Fit")
        precondition(reusedID.deviceName == "SpaceMouse Compact" && reusedID.buttonName == "Right")
        precondition(namedPress.csvRow.hasSuffix(",1,11,pressed,device,\"SpaceExplorer\",\"Fit\"\n"))
        let selection = Model(live: false)
        func status(_ vendor: Int, _ product: Int) throws -> Data {
            try JSONEncoder().encode(Status(devices: [Device(id: 1, vendor: vendor, product: product, name: "stale service name", axes: [0,0,0,0,0,0], buttons: 0)], clients: 1, reports: 0, overflows: 0, rejected: 0, foregroundApp: "", accessibility: false, mock: true))
        }
        selection.acceptStatus(try status(0x046d, 0xc627));selection.recording = 10
        selection.acceptStatus(try status(0x046d, 0xc627));precondition(selection.recording == 10)
        selection.acceptStatus(try status(0x256f, 0xc635))
        precondition(selection.recording == nil && selection.device?.displayName == "SpaceMouse Compact")
        selection.recording = 0;selection.acceptStatus(Data());precondition(selection.recording == nil)
        selection.shutdown()
        print("PASS: model-specific names/counts, sparse profile slots, named CSV edges and device-change recording cancellation")
        // An old config read must not overwrite an edit made while it was pending.
        let control = MockControl()
        let model = Model(live: false, client: control)
        let loading = Task {await model.load()}
        await control.waitForCount(1)
        model.edit {$0.gain[0] = 2}
        await control.respond(0, "{\"version\":1,\"profiles\":{\"*\":{}}}")
        await loading.value
        precondition(model.profile.gain[0] == 2)
        let saving = Task {await model.save()}
        await control.waitForCount(2)
        model.edit {$0.gain[0] = 3}
        let waiter = Task {await model.save()}
        await control.respond(1, "{\"ok\":true}")
        await control.waitForCount(3)
        let writes = await control.requests()
        let json = try JSONSerialization.jsonObject(with: Data(writes[2].utf8)) as! [String: Any]
        let config = json["config"] as! [String: Any]
        let profile = (config["profiles"] as! [String: Any])["*"] as! [String: Any]
        precondition((profile["gain"] as! [Double])[0] == 3)
        await control.respond(2, "{\"ok\":true}")
        await saving.value;await waiter.value
        precondition(!model.hasUnsavedChanges && model.message.isEmpty)
        model.shutdown()

        // A failed write remains dirty and a subsequent successful retry clears it.
        let retryControl = MockControl();let retryModel = Model(live: false, client: retryControl)
        retryModel.edit {$0.led = false}
        let failed = Task {await retryModel.save()};await retryControl.waitForCount(1)
        await retryControl.respond(0, "{\"error\":\"disk full\"}");await failed.value
        precondition(retryModel.hasUnsavedChanges && retryModel.message == "disk full")
        let retried = Task {await retryModel.save()};await retryControl.waitForCount(2)
        await retryControl.respond(1, "{\"ok\":true}");await retried.value
        precondition(!retryModel.hasUnsavedChanges);retryModel.shutdown()

        // Polling must release the model even while a control request is suspended.
        let pollControl = MockControl()
        var polling: Model? = Model(live: false, client: pollControl)
        let weakModel = WeakModel(polling)
        polling?.startPolling();await pollControl.waitForCount(1)
        polling = nil
        precondition(weakModel.value == nil, "Polling retained the model")
        await pollControl.respond(0, "{}");await Task.yield()
        let pollRequests = await pollControl.requests();precondition(pollRequests.count == 1)
        let responsive = ResponsiveControl();let rateModel = Model(live: false, client: responsive)
        rateModel.startPolling();try await Task.sleep(nanoseconds: 2_200_000_000);rateModel.shutdown()
        let count = await responsive.statusRequests
        precondition(count >= 2 && count <= 3, "Full status requests should run at 1 Hz")
        let automaticControl = MockControl();let launcher = MockLauncher()
        let automatic = Model(live: false, client: automaticControl, launcher: launcher)
        automatic.startPolling();await automaticControl.waitForCount(1)
        await automaticControl.respond(0, "{}");await automaticControl.waitForCount(2)
        precondition(launcher.starts == 1)
        await automaticControl.respond(1, "{}");await Task.yield()
        precondition(launcher.starts == 1, "An in-flight start must not launch another process")
        let quitting = Task {await automatic.prepareToQuit()}
        await automaticControl.waitForCount(3)
        let requests = await automaticControl.requests();precondition(requests[2].contains("stop"))
        await automaticControl.respond(2, "{\"ok\":true}");await quitting.value
        precondition(launcher.terminations == 1 && !launcher.isRunning)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let finalRequests = await automaticControl.requests();precondition(finalRequests.count == 3 && launcher.starts == 1)
        let existingControl = MockControl();let replacement = MockLauncher()
        let existing = Model(live: false, client: existingControl, launcher: replacement)
        existing.startPolling();await existingControl.waitForCount(1)
        await existingControl.respond(0, "{\"devices\":[],\"clients\":1,\"reports\":0,\"overflows\":0,\"rejected\":0,\"foregroundApp\":\"\",\"accessibility\":false,\"mock\":true}")
        await existingControl.waitForCount(2)
        let takeoverRequests = await existingControl.requests()
        precondition(takeoverRequests[1].contains("stop") && replacement.starts == 0)
        await existingControl.respond(1, "{\"ok\":true}")
        await existingControl.waitForCount(3);await existingControl.respond(2, "{}")
        await existingControl.waitForCount(4)
        precondition(replacement.starts == 1, "The app must replace a detached helper with its own child")
        existing.shutdown()
        await existingControl.respond(3, "{}")
        let quitControl = MockControl();let quitModel = Model(live: false, client: quitControl)
        quitModel.edit {$0.led = false}
        let orderlyQuit = Task {await quitModel.prepareToQuit()}
        await quitControl.waitForCount(1)
        let firstQuitRequest = await quitControl.requests();precondition(firstQuitRequest[0].contains("setConfig"))
        await quitControl.respond(0, "{\"ok\":true}");await quitControl.waitForCount(2)
        let lastQuitRequest = await quitControl.requests();precondition(lastQuitRequest[1].contains("stop"))
        await quitControl.respond(1, "{\"ok\":true}");await orderlyQuit.value
        precondition(!quitModel.hasUnsavedChanges, "Quit must commit pending settings before stopping the service")
        print("PASS: stale reads, ordered/coalesced saves, failed-save retry, polling lifetime and 1 Hz control traffic")
        print("PASS: automatic service start, detached-service takeover, duplicate-start prevention and Quit without restart")
    }
}
