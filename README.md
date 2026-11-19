# SysPulse

A lightweight, native macOS hardware & system monitor built with Objective-C and AppKit for Intel and Apple Silicon systems.

## Features

- **CPU Core Temperatures**: Hardware-level reading of CPU Package and individual physical core temperatures via AppleSMC.
- **Min / Max / TjMax Headroom**: Tracks lowest, highest, and current temperatures per core with remaining headroom to the 100°C throttle limit.
- **Electrical & Power Monitoring**:
  - **Package Power**: Real-time total CPU Package power draw ($W$).
  - **Core Power (IA)**: Real-time CPU IA Core power draw ($W$).
  - **GT Power**: Real-time Graphics Technology / IGPU power draw ($W$).
  - **Core Voltage (VID)**: Real-time core operating voltage ($V$).
- **GPU Metrics**: Live GPU utilization %, dynamic GPU frequency scaling ($MHz$), and VRAM usage.
- **Core Utilization**: Mach host per-thread processor utilization tracking across all logical cores.
- **Memory & Storage**: System RAM active/wired breakdown, swap usage, and disk space tracking.
- **Menu Bar Extra**: Live CPU temperature display right in the macOS top menu bar (`⚡ XX°C`).
- **CSV Data Logging**: One-click logging to export live performance data to your Desktop.
- **Automated GitHub Issue Reporting**: Built-in feedback tool that compiles full hardware diagnostics and creates an issue automatically on GitHub.

## Build and Install

```bash
chmod +x build.sh
./build.sh
```

The application bundle will be compiled and installed directly to `/Applications/SysPulse.app`.
