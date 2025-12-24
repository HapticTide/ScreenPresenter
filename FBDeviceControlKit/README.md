# FBDeviceControlKit

A Swift Package that wraps Meta's FBDeviceControl library for iOS device discovery and management on macOS.

## Overview

FBDeviceControlKit provides a type-safe Swift API for:
- Discovering connected iOS devices
- Monitoring device connection/disconnection events
- Retrieving detailed device information (UDID, name, iOS version, etc.)

## Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../FBDeviceControlKit")
]
```

Or in Xcode: File → Add Package Dependencies → Add Local...

## Usage

### Basic Usage

```swift
import FBDeviceControlKit

// Check if FBDeviceControl is available
if FBDeviceControlService.shared.isAvailable {
    // List all connected devices
    let devices = FBDeviceControlService.shared.listDevices()
    for device in devices {
        print("Device: \(device.deviceName) (\(device.udid))")
        print("  iOS Version: \(device.productVersion ?? "Unknown")")
        print("  Model: \(device.productType ?? "Unknown")")
    }
}
```

### Observing Device Changes

```swift
import FBDeviceControlKit

let service = FBDeviceControlService.shared

// Set up callback
service.onDevicesChanged = { devices in
    print("Device list updated: \(devices.count) device(s)")
    for device in devices {
        print("  - \(device.deviceName)")
    }
}

// Start observing
service.startObserving()

// ... later ...

// Stop observing
service.stopObserving()
```

### Getting Device Details

```swift
import FBDeviceControlKit

if let device = FBDeviceControlService.shared.fetchDeviceInfo(udid: "00008030-001234567890001E") {
    print("Device Name: \(device.deviceName)")
    print("iOS Version: \(device.productVersion ?? "N/A")")
    print("Build Version: \(device.buildVersion ?? "N/A")")
    print("Serial Number: \(device.serialNumber ?? "N/A")")
    print("Architecture: \(device.architecture ?? "N/A")")
    
    // Check device state
    let state = FBDeviceStateDTO.targetState(from: device.rawState)
    print("State: \(state.description)")
    print("Available: \(state.isAvailable)")
}
```

## Architecture

```
FBDeviceControlKit/
├── Sources/
│   ├── CFBControlCore/          # ObjC - Core control abstractions
│   ├── CFBDeviceControl/        # ObjC - Device control + Bridge
│   └── FBDeviceControlKit/      # Swift - Public API
│       ├── FBDeviceControlService.swift
│       ├── FBDeviceInfoDTO.swift
│       └── FBDeviceStateDTO.swift
```

### Modules

- **CFBControlCore**: Low-level ObjC module containing async utilities, target abstractions, and core types
- **CFBDeviceControl**: ObjC module for device management, depends on CFBControlCore
- **FBDeviceControlKit**: Swift module providing type-safe public API

## Types

### FBDeviceInfoDTO

Device information data transfer object containing:
- `udid`: Device unique identifier
- `deviceName`: User-set device name
- `productVersion`: iOS version (e.g., "18.2")
- `productType`: Model identifier (e.g., "iPhone17,1")
- `buildVersion`: iOS build version
- `serialNumber`: Device serial number
- `connectionType`: USB or WiFi
- `rawState`: FBiOSTargetState value
- And more...

### FBDeviceStateDTO

Device state change event object:
- `udid`: Device identifier
- `eventType`: connected/disconnected/stateChanged
- `timestamp`: Event time
- `info`: Associated device info

### FBTargetState

Device state enumeration:
- `.creating`: Device is being created (simulators)
- `.shutdown`: Device is shut down
- `.booting`: Device is booting
- `.booted`: Device is ready ✓
- `.shuttingDown`: Device is shutting down
- `.dfu`: DFU mode
- `.recovery`: Recovery mode
- `.restoreOS`: Restoring OS
- `.unknown`: Unknown state

## License

This package includes code from [idb](https://github.com/facebook/idb) by Meta Platforms, Inc., licensed under the MIT License.

```
MIT License

Copyright (c) Meta Platforms, Inc. and affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

