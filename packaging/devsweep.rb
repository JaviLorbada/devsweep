# Homebrew formula for the command line tool, built from source at a tag.
# For a personal tap: copy it to Formula/devsweep.rb in the tap, and set url
# and sha256 to the release's source tarball (see docs/RELEASING.md).
class Devsweep < Formula
  desc "Shows how much space developer caches take up, and cleans them"
  homepage "https://github.com/JaviLorbada/devsweep"
  url "https://github.com/JaviLorbada/devsweep/archive/refs/tags/v0.1.4.tar.gz"
  sha256 "REPLACE_WITH_THE_SOURCE_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/JaviLorbada/devsweep.git", branch: "main"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "devsweep"
    bin.install ".build/release/devsweep"
  end

  test do
    assert_match "Usage: devsweep", shell_output("#{bin}/devsweep --help")
    # Report mode on an empty home finds nothing and deletes nothing.
    (testpath/"home").mkpath
    output = shell_output("HOME=#{testpath}/home DEVSWEEP_PROJECT_DIRS= #{bin}/devsweep --skip homebrew,simulators 2>&1")
    assert_match "Nothing to clean.", output
  end
end
