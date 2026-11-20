// Logitech HID++ 2.0 over Bluetooth: Logitech's BLE GATT characteristic (needs Bluetooth permission),
// with an IOHID fallback (needs Input Monitoring; macOS refuses output reports to keyboards).
import CoreBluetooth
import Foundation
import IOKit.hid

let vendorID = 0x046D
let devices: [Int: String] = [0xB35B: "MX Keys", 0xB042: "MX Master 4"]
let reportLong: UInt8 = 0x11
let devIdx: UInt8 = 0xFF
let swID: UInt8 = 0x0A
let hidppService = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")
let hidppChar = CBUUID(string: "00010001-0000-1000-8000-011F2000046D")

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacMXSwitch.log")
/// Lines of the current run (reset by `Switcher.run`).
var log: [String] = []
func say(_ s: String) {
    print(s)
    log.append(s)
}
var debugLog: [String] = []
func dbg(_ s: String) {
    print(s)
    debugLog.append(s)
}
func hex(_ r: IOReturn) -> String { "0x" + String(UInt32(bitPattern: r), radix: 16) }
func err(_ s: String) -> NSError { NSError(domain: s, code: 1) }

/// Pump the run loop until `done()` or timeout.
func spin(_ timeout: TimeInterval, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if done() { return true }
        CFRunLoopRunInMode(.defaultMode, 0.02, true)
    }
    return done()
}

protocol Transport: AnyObject {
    var label: String { get }
    /// Send a HID++ frame starting at the device index byte (no report ID).
    func send(_ frame: [UInt8]) throws
    /// Last received frame starting at the device index byte, or nil.
    var reply: [UInt8]? { get set }
    func close()
}

extension Transport {
    func request(_ feat: UInt8, _ fn: UInt8, _ params: [UInt8] = [], wait: Bool = true) throws -> [UInt8]? {
        var frame = [devIdx, feat, (fn << 4) | swID] + params
        frame += [UInt8](repeating: 0, count: 19 - frame.count)
        reply = nil
        try send(frame)
        guard wait else { return nil }
        var got: [UInt8]?
        _ = spin(2) {
            guard let r = reply else { return false }
            reply = nil
            if r.count > 4, r[1] == 0xFF, r[2] == feat {
                got = r
                return true
            }  // HID++ error
            if r.count > 2, r[1] == feat, r[2] == (fn << 4) | swID {
                got = r
                return true
            }
            return false
        }
        guard let r = got else { throw err("no response via \(label)") }
        if r[1] == 0xFF { throw err("HID++ error 0x\(String(r[4], radix: 16))") }
        return r
    }
}

// MARK: IOHID transport

final class HIDTransport: Transport {
    let label = "HID"
    let dev: IOHIDDevice
    var buf = [UInt8](repeating: 0, count: 64)
    var reply: [UInt8]?

    init(_ d: IOHIDDevice) throws {
        dev = d
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw err("HID open \(hex(r))") }
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        buf.withUnsafeMutableBufferPointer { bp in
            IOHIDDeviceRegisterInputReportCallback(
                d, bp.baseAddress!, bp.count,
                { ctx, _, _, _, id, report, len in
                    let t = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
                    var bytes = Array(UnsafeBufferPointer(start: report, count: len))
                    if bytes.first == UInt8(id) { bytes.removeFirst() }
                    if id == reportLong { t.reply = bytes }
                }, ctx)
        }
    }

    func send(_ frame: [UInt8]) throws {
        let msg = [reportLong] + frame
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(reportLong), msg, msg.count)
        guard r == kIOReturnSuccess else { throw err("HID write \(hex(r))") }
    }

    func close() { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }
}

// MARK: BLE GATT transport

final class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var chars: [UUID: CBCharacteristic] = [:]
    var transports: [UUID: BLETransport] = [:]
    var failures: [UUID: String] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {}

    func ready() -> Bool {
        _ = spin(15) { central.state != .unknown && central.state != .resetting }
        return central.state == .poweredOn
    }

    func stateDescription() -> String {
        switch central.state {
        case .unauthorized: return "Bluetooth permission not granted (System Settings > Privacy & Security > Bluetooth)"
        case .poweredOff: return "Bluetooth is off"
        default: return "Bluetooth state \(central.state.rawValue)"
        }
    }

    func open(name: String) throws -> BLETransport {
        let peers = central.retrieveConnectedPeripherals(withServices: [hidppService])
        guard let p = peers.first(where: { $0.name == name }) else {
            throw err("not found via BLE (connected: \(peers.compactMap(\.name)))")
        }
        p.delegate = self
        chars[p.identifier] = nil
        failures[p.identifier] = nil
        central.connect(p)
        guard spin(5, until: { chars[p.identifier] != nil || failures[p.identifier] != nil }),
            let ch = chars[p.identifier]
        else {
            throw err("BLE setup failed: \(failures[p.identifier] ?? "timeout")")
        }
        let t = BLETransport(p, ch, central)
        transports[p.identifier] = t
        return t
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([hidppService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        failures[p.identifier] = "connect: \(error?.localizedDescription ?? "?")"
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == hidppService }) else {
            failures[p.identifier] = "service missing \(error?.localizedDescription ?? "")"
            return
        }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            dbg("  \(p.name ?? "?") char \(c.uuid) props=0x\(String(c.properties.rawValue, radix: 16))")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) { p.setNotifyValue(true, for: c) }
        }
        guard s.characteristics?.contains(where: { $0.uuid == hidppChar }) == true else {
            failures[p.identifier] = "characteristic missing \(error?.localizedDescription ?? "")"
            return
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { dbg("  notify \(ch.uuid) error: \(e.localizedDescription)") }
        if ch.uuid == hidppChar {
            if let e = error {
                failures[p.identifier] = "notify: \(e.localizedDescription)"
            } else {
                chars[p.identifier] = ch
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        var b = Array(v)
        dbg("  <- \(ch.uuid.uuidString.prefix(8)) \(b.map { String(format: "%02x", $0) }.joined(separator: " "))")
        b.insert(devIdx, at: 0)
        transports[p.identifier]?.reply = b
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { dbg("  write error: \(e.localizedDescription)") }
        transports[p.identifier]?.writeError = error
    }
}

final class BLETransport: Transport {
    let label = "BLE"
    let p: CBPeripheral
    let ch: CBCharacteristic
    var reply: [UInt8]?
    var writeError: Error?
    let central: CBCentralManager
    init(_ p: CBPeripheral, _ ch: CBCharacteristic, _ central: CBCentralManager) {
        self.p = p
        self.ch = ch
        self.central = central
    }

    func send(_ frame: [UInt8]) throws {
        writeError = nil
        // Logitech BLE HID++ characteristic: frame without report ID and device index, 18 bytes.
        var out = Array(frame.dropFirst())
        out += [UInt8](repeating: 0, count: max(0, 18 - out.count))
        let type: CBCharacteristicWriteType = ch.properties.contains(.write) ? .withResponse : .withoutResponse
        dbg(
            "  -> \(type == .withResponse ? "req" : "cmd") \(out.map { String(format: "%02x", $0) }.joined(separator: " "))"
        )
        p.writeValue(Data(out), for: ch, type: type)
        if let e = writeError { throw err("BLE write: \(e.localizedDescription)") }
    }

    /// Drops only this app's link; the system keeps the device connected.
    func close() { central.cancelPeripheralConnection(p) }
}
