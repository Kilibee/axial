import Foundation

actor FakeWebSetup: WebSetupOperating {
    var snapshot = WebSetupSnapshot(credentialsReady: false, loopbackReady: false)
    var isTrusted = false
    var cancelled = false
    var configurationFails = false
    var inspections = 0, configurations = 0, approvals = 0
    func inspect() async throws -> WebSetupSnapshot {inspections += 1;return snapshot}
    func configureSystem() async throws {
        configurations += 1
        if cancelled {throw WebSetupFailure.cancelled}
        if configurationFails {throw WebSetupFailure.failed("Test repair failure")}
        snapshot = WebSetupSnapshot(credentialsReady: true, loopbackReady: true)
    }
    func trusted() async -> Bool {isTrusted}
    func authorizeTrust() async throws {approvals += 1;if cancelled {throw WebSetupFailure.cancelled};isTrusted = true}
    func cancel(_ value: Bool) {cancelled = value}
    func expire() {snapshot.credentialsReady = false;isTrusted = false}
    func loseLoopback() {snapshot.loopbackReady = false}
    func counts() -> (Int, Int, Int) {(inspections, configurations, approvals)}
}

@main enum WebSetupTests {
    @MainActor static func main() async throws {
        let operations = FakeWebSetup(), setup = WebSetupCoordinator(operations: FakeWebSetup())
        var retries = 0, restored = 0
        await setup.refresh(enabled: false, listening: false, listenerError: "") {retries += 1}
        precondition(!setup.ready && retries == 0 && setup.message.contains("disabled"))
        let subject = WebSetupCoordinator(operations: operations)
        await subject.refresh(enabled: true, listening: false, listenerError: "") {retries += 1}
        precondition(!subject.ready && !subject.busy && subject.message.contains("setup"))
        let initial = await operations.counts()
        precondition(initial == (1,0,0), "Checking state must never prompt for permission")
        await subject.refresh(enabled: true, listening: false, listenerError: "") {retries += 1}
        let throttled = await operations.counts();precondition(throttled == initial)
        await operations.cancel(true)
        await subject.setUp(restoreWindow: {restored += 1}) {retries += 1}
        precondition(!subject.ready && !subject.busy && subject.message.contains("cancelled") && retries == 0)
        precondition(restored == 1, "Cancellation must return focus to settings")
        await operations.cancel(false)
        await subject.setUp(restoreWindow: {restored += 1}) {retries += 1}
        precondition(subject.ready && !subject.busy && retries == 1)
        precondition(restored == 4, "Restore settings after each approval and after completion")
        let approved = await operations.counts();precondition(approved.1 == 2 && approved.2 == 1)
        await subject.refresh(enabled: true, listening: true, listenerError: "", force: true) {retries += 1}
        precondition(subject.ready && retries == 1)
        // Healthy setup does not repeat either authorization on manual retry.
        await subject.setUp {retries += 1}
        let repeated = await operations.counts();precondition(repeated.1 == approved.1 && repeated.2 == approved.2 && retries == 2)
        // Losing the alias requires repair but must not replace healthy trust.
        await operations.loseLoopback()
        await subject.refresh(enabled: true, listening: false, listenerError: "", force: true) {retries += 1}
        precondition(!subject.ready && subject.message.contains("address"))
        await subject.setUp {retries += 1}
        let repaired = await operations.counts();precondition(subject.ready && repaired.2 == 1)
        // Expiring credentials are detected without silently changing trust.
        await operations.expire()
        await subject.refresh(enabled: true, listening: true, listenerError: "", force: true) {retries += 1}
        precondition(!subject.ready && subject.message.contains("renewal"))
        await subject.setUp {retries += 1}
        let renewed = await operations.counts();precondition(subject.ready && renewed.2 == 2)
        print("PASS: app-managed setup, cancellation/retry, permission idempotence, alias repair and renewal checks")
    }
}
