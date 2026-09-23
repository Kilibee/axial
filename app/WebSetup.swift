import AppKit
import Security
import OSLog

struct WebSetupSnapshot: Decodable, Sendable {
    var credentialsReady: Bool
    var loopbackReady: Bool
    var systemReady: Bool {credentialsReady && loopbackReady}
}

enum WebSetupFailure: LocalizedError {
    case cancelled, failed(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Setup was cancelled. You can approve it when you are ready."
        case .failed(let message): return message
        }
    }
}

protocol WebSetupOperating: Sendable {
    func inspect() async throws -> WebSetupSnapshot
    func configureSystem() async throws
    func trusted() async -> Bool
    func authorizeTrust() async throws
}

struct NativeWebSetup: WebSetupOperating {
    let helper: URL
    private static let directory = URL(fileURLWithPath: "/Library/Application Support/Axial/Web", isDirectory: true)

    static func execute(_ executable: URL, _ arguments: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process(), output = Pipe()
            process.executableURL = executable;process.arguments = arguments
            process.standardOutput = output;process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: data, encoding: .utf8) ?? ""
                Logger(subsystem: "pro.jest.Axial", category: "WebSetup").error("Setup helper failed: \(message, privacy: .public)")
                if message.contains("(-128)") {throw WebSetupFailure.cancelled}
                throw WebSetupFailure.failed("macOS could not complete web setup. Please retry and approve the system prompts.")
            }
            return data
        }.value
    }
    func inspect() async throws -> WebSetupSnapshot {
        try JSONDecoder().decode(WebSetupSnapshot.self, from: await Self.execute(helper, ["--check"]))
    }
    // Only a fixed, bundled native helper is elevated. No downloaded commands,
    // shell scripts, host lists, or external crypto tools are involved.
    func configureSystem() async throws {
        let command = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "' --install"
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await Self.execute(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "do shell script \"\(literal)\" with administrator privileges"])
    }
    private static func certificate(_ name: String) throws -> SecCertificate {
        let file = directory.appendingPathComponent(name)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o022 == 0 else {
            throw WebSetupFailure.failed("Web credentials need repair before they can be approved.")
        }
        let pem = try String(contentsOf: file, encoding: .utf8)
        let body = pem.split(separator: "\n").filter {!$0.hasPrefix("-----")}.joined()
        guard let der = Data(base64Encoded: body), let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw WebSetupFailure.failed("Web credentials need repair before they can be approved.")
        }
        return certificate
    }
    private static func evaluateTrust() -> Bool {
        guard let leaf = try? certificate("server.crt"), let root = try? certificate("root.crt") else {return false}
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf, root] as CFArray, SecPolicyCreateSSL(true, "127.51.68.120" as CFString), &trust) == errSecSuccess,
              let trust else {return false}
        SecTrustSetNetworkFetchAllowed(trust, false)
        // Do not override anchors or ignore verification failures. This checks
        // the same OS trust that web clients use, not merely our own CA file.
        return SecTrustEvaluateWithError(trust, nil)
    }
    func trusted() async -> Bool {await Task.detached {Self.evaluateTrust()}.value}
    func authorizeTrust() async throws {
        try await Task.detached {
            let root = try Self.certificate("root.crt")
            // Acquire the existing system right from the GUI app's session.
            // Never change authorizationdb or allow a headless installer to
            // bypass this approval. The certificate is limited to loopback TLS.
            var authorization: AuthorizationRef?
            let status = "com.apple.trust-settings.admin".withCString { name in
                var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { pointer in
                    var rights = AuthorizationRights(count: 1, items: pointer)
                    return AuthorizationCreate(&rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], &authorization)
                }
            }
            defer {if let authorization {AuthorizationFree(authorization, [])}}
            if status == errAuthorizationCanceled {throw WebSetupFailure.cancelled}
            guard status == errAuthorizationSuccess else {
                throw WebSetupFailure.failed("Certificate approval needs an active macOS login session. Retry from Axial's settings window.")
            }
            let constraints: [String: Any] = [
                kSecTrustSettingsPolicy: SecPolicyCreateSSL(true, nil),
                kSecTrustSettingsPolicyString: "127.51.68.120",
                kSecTrustSettingsResult: SecTrustSettingsResult.trustRoot.rawValue
            ]
            let result = SecTrustSettingsSetTrustSettings(root, .admin, constraints as CFDictionary)
            if result == errSecUserCanceled {throw WebSetupFailure.cancelled}
            guard result == errSecSuccess, Self.evaluateTrust() else {
                throw WebSetupFailure.failed("macOS has not approved the local web certificate. Retry to authorize it.")
            }
        }.value
    }
}

@MainActor final class WebSetupCoordinator: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published private(set) var message = "Checking web navigation setup…"
    private let operations: any WebSetupOperating
    private var lastCheck: Date = .distantPast
    init(operations: any WebSetupOperating) {self.operations = operations}

    func refresh(enabled: Bool, listening: Bool, listenerError: String, force: Bool = false, retry: () async -> Void) async {
        guard !busy else {return}
        guard enabled else {ready = false;lastCheck = .distantPast;message = "Web navigation is disabled.";return}
        guard force || Date().timeIntervalSince(lastCheck) >= 60 else {return}
        busy = true;defer {busy = false};lastCheck = Date()
        do {
            let snapshot = try await operations.inspect()
            guard snapshot.systemReady else {
                ready = false;message = snapshot.credentialsReady ? "Local web address needs setup. Approve setup to repair it." : "Web navigation needs setup or certificate renewal.";return
            }
            guard await operations.trusted() else {ready = false;message = "Local web certificate needs your approval.";return}
            let wasReady = ready;ready = true
            if !wasReady || !listening {await retry()}
            message = listening ? "Web navigation is ready." : (listenerError.isEmpty ? "Starting web navigation…" : listenerError)
        } catch {ready = false;message = "Could not check web setup. Retry from the installed Axial app."}
    }
    func setUp(restoreWindow: () -> Void = {}, retry: () async -> Void) async {
        guard !busy else {return}
        busy = true;ready = false;message = "Waiting for macOS approval…"
        defer {busy = false;lastCheck = Date();restoreWindow()}
        do {
            let snapshot = try await operations.inspect()
            if !snapshot.systemReady {try await operations.configureSystem();restoreWindow()}
            guard try await operations.inspect().systemReady else {throw WebSetupFailure.failed("Local web setup did not finish. Retry to repair it.")}
            if !(await operations.trusted()) {try await operations.authorizeTrust();restoreWindow()}
            guard await operations.trusted() else {throw WebSetupFailure.failed("The certificate still needs approval.")}
            await retry();ready = true;message = "Web navigation setup is complete."
        } catch {message = error.localizedDescription}
    }
}
