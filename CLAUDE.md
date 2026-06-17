# Agent & AI Assistant Guidelines for CoolMyMac

If you are an AI coding assistant (like Claude, Cursor, Windsurf) operating in this repository, please adhere to the following architecture rules and context.

## Project Structure
- **`CoolMyMac-App/`**: Contains the Xcode Project.
  - **`App/`**: The SwiftUI MenuBar application.
  - **`Daemon/`**: The LaunchDaemon (`root`) responsible for IOKit writes.
- **`CoolMyMac-CLI/`**: The Swift Package for the command-line tool.
- **`SMCKit/`**: The core framework for interfacing with the macOS SMC.

## Architectural Rules
1. **XPC Communication**: The `SMCKit` must remain agnostic. It does not know if it is running in the App, the CLI, or the Daemon. The App and CLI run unprivileged and MUST use XPC (`CoolMyMacXPCProtocol`) to ask the Daemon to perform fan control operations. Do not import App UI or Foundation classes into the Daemon directly.
2. **Apple Silicon vs Intel**: Do not hardcode sensors for one architecture over the other. All SMC calls route through `SMCController.swift`, which dynamically chooses `AppleSiliconSMC.swift` or `AppleSMC.swift` based on runtime `sysctl` checks.
3. **Build System**: The CLI is built as a Universal Binary via a Run Script phase in the main Xcode project (`Build & Embed CLI`). Do not modify Xcode phases to build exclusively for `arm64`; always use `$(ARCHS_STANDARD)` for Universal Binaries. Note: The run script relies on `env -i` to create a clean environment so Xcode's variables don't pollute the SPM build. Do NOT remove `env -i` from this script!
4. **Code Signing**: `SMAppService` daemon registration requires a real team signature — **never use `CODE_SIGN_IDENTITY="-"` (ad-hoc) when building daemon changes**, it will silently break daemon registration. Let xcodebuild use the keychain cert by omitting that flag. If you add new capabilities or entitlements, ensure they match across both the App and the Daemon.
5. **Swift Concurrency**: This project targets macOS 15.0+ and adheres to strict Swift concurrency rules. Use `Sendable` types and actors where appropriate. If you must use `@unchecked Sendable`, strictly document why it is safe.

## Release & Distribution
- **DMG Creation**: To build, package, sign, and notarize the app for release, run `./scripts/release.sh`. This requires the `CoolMyMac-Notary` keychain profile to be configured on the host machine.
- **Homebrew Cask**: The Homebrew formula is maintained via a Git submodule in `homebrew-coolmymac/`. When creating a new release, the SHA256 in `homebrew-coolmymac/Casks/coolmymac.rb` must be updated to match the final notarized DMG hash.

## Common Agent Tasks

**Compile check (app only, no install):**
```bash
xcodebuild clean build -project CoolMyMac-App/CoolMyMac.xcodeproj -scheme CoolMyMac ONLY_ACTIVE_ARCH=YES
```

**Build and install to /Applications (app + daemon):**
```bash
# Build — omit CODE_SIGN_IDENTITY so keychain cert is used (required for daemon SMAppService registration)
xcodebuild build -project CoolMyMac-App/CoolMyMac.xcodeproj -scheme CoolMyMac -configuration Debug ONLY_ACTIVE_ARCH=YES

# Get build output path
BUILD_DIR=$(xcodebuild -project CoolMyMac-App/CoolMyMac.xcodeproj -scheme CoolMyMac -configuration Debug -showBuildSettings ONLY_ACTIVE_ARCH=YES 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3}')

# Quit running app, install, relaunch
pkill -x CoolMyMac; sleep 1
sudo cp -Rf "$BUILD_DIR/CoolMyMac.app" /Applications/
open /Applications/CoolMyMac.app
```

**Daemon lifecycle:**
```bash
sudo launchctl print system/com.coolmymac.app.daemon   # status + PID
sudo launchctl kickstart -k system/com.coolmymac.app.daemon  # force restart
sudo tail -f /var/log/com.coolmymac.daemon.log          # stdout log
sudo tail -f /var/log/com.coolmymac.daemon.error.log    # stderr log
```

Note: The daemon is registered by `SMAppService` when the app launches — do not manually load/unload it with `launchctl bootstrap/bootout`. The `CoolMyMac-Daemon` binary is a separate build target embedded into the app bundle via the `Embed Daemon` run script phase; both are built together by the `CoolMyMac` scheme.

**CLI:**
```bash
cd CoolMyMac-CLI && swift build
```

**SMC logic:** refer to `MockSMCProvider.swift` for dependency injection in tests.
