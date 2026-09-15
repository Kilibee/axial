import Foundation

@_silgen_name("AxialRequest") private func nativeRequest(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

protocol ServiceRequesting: Sendable {
    func request(_ text: String) async -> Data
}

// One ordered I/O lane. Blocking local IPC never occupies the main actor or a
// Swift cooperative executor, and an older save cannot overtake a newer one.
final class ServiceClient: ServiceRequesting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "pro.jest.control", qos: .userInitiated)
    func request(_ text: String) async -> Data {
        await withCheckedContinuation { continuation in
            queue.async {
                let data = text.withCString { p -> Data in
                    guard let result = nativeRequest(p) else {return Data()}
                    defer {free(result)}
                    return Data(bytes: result, count: strlen(result))
                }
                continuation.resume(returning: data)
            }
        }
    }
}
