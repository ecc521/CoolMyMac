cask "coolmymac" do
  version "1.0.2"
  # You must update this sha256 to match the exact hash of your CoolMyMac.zip on each release. 
  # You can generate the hash by running `shasum -a 256 CoolMyMac.zip` in terminal.
  sha256 "REPLACE_WITH_ZIP_SHA256"

  url "https://github.com/ecc521/CoolMyMac/releases/download/v#{version}/CoolMyMac.zip"
  name "CoolMyMac"
  desc "Menu bar app and CLI to monitor and control Apple Silicon fans"
  homepage "https://github.com/ecc521/CoolMyMac"

  # Requires macOS 15.0 or later as defined in your project
  depends_on macos: ">= :sequoia"

  # This tells Homebrew to drag CoolMyMac.app into the /Applications folder
  app "CoolMyMac.app"

  # This automatically symlinks the CLI into /usr/local/bin/coolmymac!
  binary "CoolMyMac.app/Contents/MacOS/coolmymac"

  # Cleans up preferences if the user runs `brew uninstall --zap coolmymac`
  zap trash: [
    "~/Library/Preferences/com.coolmymac.app.plist",
    "~/Library/Preferences/com.coolmymac.daemon.plist"
  ]
end
