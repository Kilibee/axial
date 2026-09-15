import Foundation

@_silgen_name("AxialDeviceCount") private func deviceCount() -> UInt32
@_silgen_name("AxialDeviceIdentity") private func deviceIdentity(_ index: UInt32) -> UInt32
@_silgen_name("AxialDeviceName") private func deviceName(_ identity: UInt32) -> UnsafePointer<CChar>?
@_silgen_name("AxialDeviceButtonName") private func deviceButtonName(_ identity: UInt32, _ slot: UInt32) -> UnsafePointer<CChar>?
@_silgen_name("AxialDeviceButtonSlots") private func deviceButtonSlots(_ identity: UInt32, _ slots: UnsafeMutablePointer<UInt8>, _ capacity: UInt32) -> UInt32

struct ControllerButton: Identifiable {
    let id: Int // Persistent profile slot, not the visible row number.
    let name: String
}
struct ControllerLayout {
    let name: String
    let buttons: [ControllerButton]
    let names: [String?]
    func buttonName(slot: Int) -> String {
        (names.indices.contains(slot) ? names[slot] : nil) ?? "Unknown button (\(slot + 1))"
    }
}
enum DeviceCatalog {
    // One native hardware catalog, converted once. No JSON or string building
    // in the HID callback; names are resolved when the UI consumes log entries.
    static let layouts: [UInt32: ControllerLayout] = {
        var result: [UInt32: ControllerLayout] = [:]
        for index in 0..<deviceCount() {
            let identity = deviceIdentity(index)
            guard let name = deviceName(identity) else {continue}
            var slots = [UInt8](repeating: 0, count: 32)
            let count = Int(deviceButtonSlots(identity, &slots, 32))
            let names: [String?] = (0..<32).map {slot in deviceButtonName(identity, UInt32(slot)).map {String(cString: $0)}}
            let buttons = slots.prefix(count).map {ControllerButton(id: Int($0), name: names[Int($0)]!)}
            result[identity] = ControllerLayout(name: String(cString: name), buttons: buttons, names: names)
        }
        return result
    }()
    static func identity(vendor: Int, product: Int) -> UInt32? {
        guard (0...65535).contains(vendor), (0...65535).contains(product) else {return nil}
        return UInt32(vendor) << 16 | UInt32(product)
    }
}
