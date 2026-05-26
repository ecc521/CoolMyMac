cask "coolmymac" do
  version "1.0.4"
  sha256 "5bfb2c3b7f80ad0879cf159db5d95b36941b7bbbcd92cc504d16267f68979f19"

  url "https://github.com/tuckerwillenborg/CoolMyMac/releases/download/v#{version}/CoolMyMac.dmg"
  name "CoolMyMac"
  desc "Advanced SMC fan control and thermal monitoring for Apple Silicon and Intel Macs"
  homepage "https://github.com/tuckerwillenborg/CoolMyMac"

  depends_on macos: ">= :sequoia" # Wait, actually SMAppService requires ventura, but the app is built for Sequoia (15.0).
  # We'll set depends_on macos: ">= :sequoia"

  app "CoolMyMac.app"
end
