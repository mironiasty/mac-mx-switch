# MacMXSwitch

Switch your desk to another computer with one click: moves a Logitech **MX Keys** keyboard and **MX Master 4** mouse to another Easy-Switch channel and changes the external monitor's input, all from macOS.

- **Peripherals:** HID++ 2.0 feature `0x1814` (CHANGE_HOST), sent over Logitech's Bluetooth LE GATT HID++ channel. Falls back to IOHID if BLE is unavailable (macOS refuses writes to keyboards that way, so BLE is the main path).
- **Monitor:** DDC/CI VCP `0x60` (input source) via the private `IOAVService` I2C API on Apple Silicon, the same approach as [m1ddc](https://github.com/waydabber/m1ddc).

Before switching, it checks that every device is reachable. If any of them fails, nothing is switched. The monitor goes first, so if it fails you still have your keyboard and mouse here to see the error.

## Requirements

- macOS 13 or later on Apple Silicon (the DDC code relies on Apple Silicon display services)
- Xcode Command Line Tools (`swiftc`)
- Logitech MX Keys and/or MX Master 4 paired over **Bluetooth** (not the Bolt/Unifying receiver)
- An external monitor that supports DDC/CI input switching

## Install

Download `MacMXSwitch-<version>.zip` from [Releases](https://github.com/mironiasty/mac-mx-switch/releases), unzip, and move `MacMXSwitch.app` to `/Applications` or `~/Applications`. Release builds are signed with a Developer ID and notarized by Apple.

## Build from source

```sh
./build.sh
```

This compiles `main.swift` + `DDC.swift`, wraps them in an ad-hoc signed `MacMXSwitch.app` (bundle ID `asia.miron.macmxswitch`), and installs it to `~/Applications`. For signed releases, see [RELEASING.md](RELEASING.md).

## Usage

Launch it from Spotlight/Finder or run the binary directly:

```sh
~/Applications/MacMXSwitch.app/Contents/MacOS/MacMXSwitch --host 2 --input 15
```

| Flag | Meaning | Default |
| --- | --- | --- |
| `--host N` | Easy-Switch channel to switch to (1-based) | `1` |
| `--input N` | Monitor input value (VCP `0x60`) | `17` |
| `--no-monitor` | Don't touch the monitor | |
| `--monitor-only` | Only switch the monitor | |
| `--dry-run` | Probe devices and report, switch nothing | |

Monitor input values depend on the monitor. Common ones: `15` = DisplayPort 1, `16` = DisplayPort 2, `17` = HDMI 1, `18` = HDMI 2, `27` = USB-C. A `--dry-run` shows the current input of each monitor.

When launched from Finder/Spotlight, a dialog appears only if something failed (or on a dry run). Each run writes a log to `~/Library/Logs/MacMXSwitch.log`.

To switch to a machine other than channel 1 / input 17 with one click, wrap the binary with the right flags in a Shortcut, a shell alias, or a hotkey tool.

## Permissions

- **Bluetooth** (System Settings → Privacy & Security → Bluetooth): required for the BLE path. macOS will prompt on first run.
- **Input Monitoring:** only needed for the IOHID fallback.

## Supported devices

Product IDs are hard-coded in `main.swift`:

| Device | PID |
| --- | --- |
| MX Keys | `0xB35B` |
| MX Master 4 | `0xB042` |

To support other HID++ 2.0 Logitech devices with Easy-Switch, add their Bluetooth PIDs to the `devices` map.

## Disclaimer

Not affiliated with Logitech. "MX", "MX Keys", and "MX Master" are trademarks of Logitech.
