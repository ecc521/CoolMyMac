# Agent & AI Assistant Guidelines for CoolMyMac

If you are an AI coding assistant (like Claude, Cursor, Windsurf) operating in this repository, please adhere to the following architecture rules and context.

## Project Structure
- **`CoolMyMac-App/`**: Contains the Xcode Project.
  - **`App/`**: The SwiftUI MenuBar application.
  - **`Daemon/`**: The LaunchDaemon (`root`) responsible for IOKit writes.
- **`CoolMyMac-CLI/`**: The Swift Package for the command-line tool.
- **`SMCKit/`**: The core framework for interfacing with the macOS SMC.

## Architectural Rules
1. **XPC Communication**: The `SMCKit` must remain agnostic. It does not know if it is running in the App, the CLI, or the Daemon. The App and CLI run unprivileged and MUST use XPC (`CoolMyMacXPCProtocol`) to ask the Daemon to perform fan control operations.
2. **Apple Silicon vs Intel**: Do not hardcode sensors for one architecture over the other. All SMC calls route through `SMCController.swift`, which dynamically chooses `AppleSiliconSMC.swift` or `AppleSMC.swift` based on runtime `sysctl` checks.
3. **Build System**: The CLI is built as a Universal Binary via a Run Script phase in the main Xcode project (`Build & Embed CLI`). Do not modify Xcode phases to build exclusively for `arm64`; always use `$(ARCHS_STANDARD)` for Universal Binaries.
4. **Code Signing**: Modifications to the Daemon require proper code signing with a Developer ID. If you add new capabilities or entitlements, ensure they match across both the App and the Daemon to satisfy `SMAppService` requirements.

## Common Agent Tasks
- To test compilation: run `xcodebuild clean build -project CoolMyMac-App/CoolMyMac.xcodeproj -scheme CoolMyMac`
- To test the CLI: run `cd CoolMyMac-CLI && swift build`
- To test SMC logic, refer to `MockSMCProvider.swift` for dependency injection.
