# FPP View

A cross-platform Flutter app to discover and control [Falcon Player (FPP)](https://github.com/FalconChristmas/fpp) devices on the local network.

Runs on Windows, Android, iOS, macOS, and Linux. (Web is not supported — browsers cannot open the raw UDP/mDNS sockets discovery requires.)

## Features

- **Zero-config discovery** of FPP instances via:
  - UDP MultiSync ping (multicast `239.70.80.80` + broadcast, port `32320`)
  - mDNS (`_fppd._udp`)
  - Peer pull from any found device (`/api/fppd/multiSyncSystems`)
  - Manual add by hostname/IP (persisted across launches)
- **Device list** with live status: playback state, hostname, IP, version, platform, and mode.
- **Per-device controls**:
  - Start / stop hardware test pattern (RGB chase)
  - Test a single model's channel range
  - Play / stop a single sequence
  - Start a playlist; stop gracefully or immediately
  - View channel outputs (pixel / serial / matrix / other)
  - Open the device's web UI
- **Bulk actions**: start/stop testing on all devices at once.

## Architecture

| Path | Responsibility |
|------|----------------|
| `lib/models/fpp_device.dart` | Device model + version-aware JSON parsing |
| `lib/models/fpp_output.dart` | Channel-output parsing |
| `lib/services/fpp_api.dart` | FPP HTTP REST client |
| `lib/services/fpp_discovery.dart` | UDP + mDNS + peer discovery |
| `lib/services/device_manager.dart` | Device list, status polling, persistence |
| `lib/ui/` | Device list, detail/control, and outputs pages |

## Running

```
flutter pub get
flutter run -d windows   # or: android, macos, linux
```

On Windows, building plugins requires **Developer Mode** to be enabled
(Settings -> For Developers) for symlink support.

## Testing

```
flutter test
```

Unit tests cover the discovery packet decoder, sysinfo/status JSON parsing, and IP persistence.
