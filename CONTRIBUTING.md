# Contributing to CoolMyMac

First off, thank you for considering contributing to CoolMyMac! It's people like you that make CoolMyMac such a great tool for macOS thermal management.

## Setup Your Development Environment

1. Clone the repository: `git clone https://github.com/ecc521/CoolMyMac.git`
2. Open `CoolMyMac-App/CoolMyMac.xcodeproj` in Xcode.
3. Configure your **Code Signing Identity**:
   - macOS requires `SMAppService` daemons to have matching code signatures.
   - Go to the `CoolMyMac` target -> Signing & Capabilities and select your Personal Team.
   - Repeat for the `CoolMyMac-Daemon` target.
4. Hit **Run** (Cmd + R) to compile the project.

### Modifying the CLI
The `CoolMyMac-CLI` is built as a Swift Package. When building the main Xcode project, a Run Script phase automatically compiles the CLI as a universal binary and embeds it in the App bundle.
To test CLI changes quickly:
```bash
cd CoolMyMac-CLI
swift build
swift run coolmymac temps
```

## Code Style & Conventions

- **Swift Concurrency**: The project adopts strict Swift concurrency. Be mindful of actor boundaries and `Sendable` types. When using `@unchecked Sendable`, please document *why* it is safe.
- **XPC Boundary**: `CoolMyMac-App` and `CoolMyMac-Daemon` communicate strictly via XPC (`CoolMyMacXPCProtocol.swift`). Do not import UI or App-specific logic into the Daemon. The Daemon must remain a minimal, headless background service.
- **SMCKit Agnosticism**: `SMCKit` must not know whether it's running in the CLI, App, or Daemon. Avoid using `AppKit` or `Foundation`'s UI libraries inside `SMCKit`.

## Pull Requests

- Ensure your code compiles without warnings on the latest version of Xcode.
- Please test your changes on both Apple Silicon and Intel hardware if possible. If you can only test one, mention it in the PR description!
- Create a feature branch and submit a PR against `main`.
