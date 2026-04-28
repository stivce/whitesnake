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

## Releases

Releases are automated via GitHub Actions. Pushing a version tag builds the app, packages it as a DMG, signs it with Sparkle's EdDSA key, publishes a GitHub Release, and updates `appcast.xml` so the in-app updater picks it up automatically.

```bash
git tag v1.0.0
git push origin v1.0.0
```

### First-time setup

1. **Generate Sparkle keys** (run once, requires the Sparkle tools):
   ```bash
   curl -sSL https://github.com/sparkle-project/Sparkle/releases/download/2.7.1/Sparkle-2.7.1.tar.xz \
     | tar -xJ --strip-components=1 -C /tmp/sparkle bin/generate_keys
   /tmp/sparkle/generate_keys
   ```
   This prints a **private key** and a **public key**.

2. **Add the private key** as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`
   (repo → Settings → Secrets → Actions).

3. **Paste the public key** into `AppBundle/Info.plist` replacing `REPLACE_WITH_PUBLIC_KEY`
   for the `SUPublicEDKey` entry.

## Architecture

- **`SystemCheck`** — protocol every check conforms to. Declares `check()`, `fix()`, and `fix(progressHandler:)`.
- **`CommandRunner`** — wraps `Process` with async/await, streaming output, and timeout support.
- **`DashboardViewModel`** — `@MainActor ObservableObject` that owns all checks and drives UI state.
- All install progress is streamed line-by-line and parsed into `InstallProgress` structs for the live progress indicator.
