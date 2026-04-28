# Whitesnake

A macOS menu-bar style app that checks and fixes your development environment in one place.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## What it checks

| Check | Auto-fix |
|---|---|
| macOS Update | Opens Software Update settings |
| Xcode Command Line Tools | Triggers system installer |
| Homebrew | Opens brew.sh |
| Rosetta 2 | Installs via `softwareupdate` |
| Git | Installs via Homebrew |
| Ansible | Installs via Homebrew |

## Requirements

- macOS 14 or later
- Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Build & run

```bash
bash Scripts/build-app-bundle.sh
open Build/Whitesnake.app
```

The script compiles the Swift package, packages the binary into a `.app` bundle, and generates the app icon from `whitesnake.png`.

## Project structure

```
Sources/Whitesnake/
  App/        — entry point and window setup
  Core/       — SystemCheck protocol, CommandRunner, shared types
  Checks/     — one file per check (Git, Homebrew, Ansible, …)
  UI/         — SwiftUI views and DashboardViewModel
Tests/
  WhitesnakeTests/
    Checks/   — GitCheck unit tests
    Core/     — CommandRunner unit tests
    UI/       — DashboardViewModel unit tests
```

## Architecture

- **`SystemCheck`** — protocol every check conforms to. Declares `check()`, `fix()`, and `fix(progressHandler:)`.
- **`CommandRunner`** — wraps `Process` with async/await, streaming output, and timeout support.
- **`DashboardViewModel`** — `@MainActor ObservableObject` that owns all checks and drives UI state.
- All install progress is streamed line-by-line and parsed into `InstallProgress` structs for the live progress indicator.
