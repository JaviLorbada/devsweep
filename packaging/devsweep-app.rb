# Homebrew cask template for the app. For a personal tap: copy it to
# Casks/devsweep-app.rb in the tap and set version and sha256 to the release's
# app zip (see docs/releasing.md). Named devsweep-app so it doesn't clash
# with the devsweep formula for the command line tool.
cask "devsweep-app" do
  version "0.1.4"
  sha256 "REPLACE_WITH_THE_APP_ZIP_SHA256"

  url "https://github.com/JaviLorbada/devsweep/releases/download/v#{version}/DevSweep-#{version}.zip"
  name "DevSweep"
  desc "Shows how much space developer caches take up, and cleans them"
  homepage "https://github.com/JaviLorbada/devsweep"

  depends_on macos: ">= :tahoe"

  app "DevSweep.app"

  zap trash: [
    "~/Library/Application Support/DevSweep",
    "~/Library/Preferences/com.javilorbada.devsweep.plist",
  ]
end
