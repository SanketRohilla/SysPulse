# SysPulse

A lightweight, native macOS hardware monitor built with Objective-C and AppKit.

## Features

- **Hardware Sensors**: Real-time reading of CPU package and individual core temperatures via AppleSMC.
- **Min/Max Tracking**: Tracks lowest, highest, and current temperatures per core, along with thermal margin to TjMax.
- **Electrical Metrics**: Live CPU package power consumption (Watts) and core voltage (VID).
- **Core Utilization**: Mach host per-thread processor utilization tracking.
- **GPU & Memory**: Intel GPU utilization, VRAM usage, and system memory stats.
- **Menu Bar Item**: Displays live CPU temperature in the macOS menu bar.
- **CSV Data Logging**: Option to export thermal data to a local CSV file.

## Build and Install

```bash
chmod +x build.sh
./build.sh
```
