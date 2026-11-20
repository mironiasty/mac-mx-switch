// One switch run: query every device first, then switch only if all of them are ready.
import Foundation
import IOKit.hid

struct Options {
    /// Easy-Switch channel, 1-based.
    var host = 1
    /// Monitor input (DDC VCP 0x60 value); nil leaves the monitor alone.
    var monitorInput: UInt16? = 17
    var monitorOnly = false
    var dryRun = false
}

struct RunResult {
    var ok: Bool
    var lines: [String]
    /// The user was asked whether to switch without the monitor (so they've already seen the problem).
    var asked = false
}

/// Query CHANGE_HOST over a transport; returns its feature index.
func probe(_ t: Transport, _ name: String) throws -> UInt8 {
    let idx = try t.request(0x00, 0, [0x18, 0x14])![3]
    if idx == 0 { throw err("CHANGE_HOST not supported") }
    let info = try t.request(idx, 0)!
    say("\(name): on channel \(Int(info[4]) + 1) of \(info[3]) [\(t.label)]")
    return idx
}

final class Switcher {
    /// Created on first use so the monitor-only path never asks for Bluetooth.
    private lazy var ble = BLE()
    private var hidByName: [String: IOHIDDevice]?

    /// IOHID devices by name (only needed if BLE fails; requires Input Monitoring).
    private func hidDevice(_ name: String) -> IOHIDDevice? {
        if hidByName == nil {
            if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
                say("(Input Monitoring not granted; HID fallback unavailable)")
            }
            let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            // The HID++ collection (0xFF43/0x0202) is a secondary usage pair, not the primary usage.
            IOHIDManagerSetDeviceMatching(
                mgr,
                [
                    kIOHIDVendorIDKey: vendorID,
                    kIOHIDDeviceUsagePageKey: 0xFF43,
                    kIOHIDDeviceUsageKey: 0x0202,
                ] as CFDictionary)
            var m: [String: IOHIDDevice] = [:]
            for d in IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> ?? [] {
                let pid = (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) ?? 0
                if let n = devices[pid], m[n] == nil { m[n] = d }
            }
            hidByName = m
        }
        return hidByName![name]
    }

    /// - Parameter confirmWithoutMonitor: called when the monitor can't be switched but keyboard and
    ///   mouse can; gets the monitor problems and returns whether to switch them anyway.
    ///   Peripheral failures always block everything.
    func run(_ o: Options, confirmWithoutMonitor: ([String]) -> Bool = { _ in false }) -> RunResult {
        log = []
        debugLog = []
        var ok = true
        var asked = false
        var monitorProblems: [String] = []
        var ready: [(Transport, UInt8, String)] = []

        var displays: [CFTypeRef] = []
        if let input = o.monitorInput {
            do {
                displays = try DDC.externalServices()
                for (i, av) in displays.enumerated() {
                    let cur = (try? DDC.getVCP(av, DDC.vcpInput)).map(String.init) ?? "unknown"
                    say("Monitor \(i + 1): input \(cur) (target \(input))")
                }
            } catch {
                let msg = "Monitor: failed: \((error as NSError).domain)"
                monitorProblems.append(msg)
                if o.monitorOnly { ok = false }
                say(msg)
            }
        }

        let bleReady = o.monitorOnly ? false : ble.ready()
        for name in o.monitorOnly ? [] : Set(devices.values).sorted() {
            var attempts: [String] = []
            var done = false
            // 1) BLE GATT (needs only Bluetooth permission; works for keyboards too)
            if bleReady {
                do {
                    let t = try ble.open(name: name)
                    ready.append((t, try probe(t, name), name))
                    done = true
                } catch { attempts.append("BLE: " + (error as NSError).domain) }
            } else {
                attempts.append(ble.stateDescription())
            }
            // 2) IOHID fallback (needs Input Monitoring; macOS blocks writes to keyboards)
            if !done {
                if let d = hidDevice(name) {
                    do {
                        let t = try HIDTransport(d)
                        do {
                            ready.append((t, try probe(t, name), name))
                            done = true
                        } catch {
                            t.close()
                            throw error
                        }
                    } catch { attempts.append("HID: " + (error as NSError).domain) }
                } else {
                    attempts.append("HID: not listed")
                }
            }
            if !done {
                ok = false
                say("\(name): failed: " + attempts.joined(separator: "; "))
            }
        }

        if o.dryRun {
            say("(dry run, nothing switched)")
        } else if !ok {
            say("Not switching anything because a device failed.")
        } else {
            // Monitor first: if it fails we still have keyboard + mouse here to answer the prompt.
            if let input = o.monitorInput {
                for (i, av) in displays.enumerated() {
                    do {
                        try DDC.setVCP(av, DDC.vcpInput, input)
                        say("Monitor \(i + 1) -> input \(input)")
                    } catch {
                        let msg = "Monitor \(i + 1): switch failed: \((error as NSError).domain)"
                        monitorProblems.append(msg)
                        if o.monitorOnly { ok = false }
                        say(msg)
                    }
                }
            }
            if !monitorProblems.isEmpty && !ready.isEmpty {
                asked = true
                if confirmWithoutMonitor(monitorProblems) {
                    say("Switching keyboard and mouse without the monitor (confirmed).")
                } else {
                    ok = false
                    say("Cancelled: nothing else switched.")
                }
            }
            for (t, idx, name) in ok ? ready : [] {
                do {
                    _ = try t.request(idx, 1, [UInt8(o.host - 1)], wait: false)
                    _ = spin(0.3) { false }  // let BLE writes flush
                    say("\(name) -> switched to \(o.host)")
                } catch {
                    ok = false
                    say("\(name): switch failed: \((error as NSError).domain)")
                }
            }
        }
        for (t, _, _) in ready { t.close() }

        writeLog(o)
        return RunResult(ok: ok, lines: log, asked: asked)
    }

    private func writeLog(_ o: Options) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let head = "[\(stamp)] host=\(o.host) input=\(o.monitorInput.map(String.init) ?? "off") dryRun=\(o.dryRun)"
        let text = ([head] + log + ["--- debug ---"] + debugLog).joined(separator: "\n") + "\n"
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
