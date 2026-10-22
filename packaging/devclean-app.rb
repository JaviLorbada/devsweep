# Homebrew cask template for the app. For a personal tap: copy it to
# Casks/devclean-app.rb in the tap and set version and sha256 to the release's
# app zip (see docs/RELEASING.md). Named devclean-app so it doesn't clash
# with the devclean formula for the command line tool.
cask "devclean-app" do
  version "0.1.0"
  sha256 "REPLACE_WITH_THE_APP_ZIP_SHA256"

  url "https://github.com/JaviLorbada/devclean/releases/download/v#{version}/DevClean-#{version}.zip"
  name "DevClean"
  desc "Shows how much space developer caches take up, and cleans them"
  homepage "https://github.com/JaviLorbada/devclean"

  depends_on macos: ">= :tahoe"

  app "DevClean.app"

  zap trash: [
    "~/Library/Application Support/DevClean",
    "~/Library/Preferences/com.javilorbada.devclean.plist",
  ]
end
