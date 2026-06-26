# Developer tooling for ZenTab. Install everything with:  brew bundle
# (or run bin/setup, which also builds once and configures the editor LSP).
#
# Xcode itself is not managed here; install it from the App Store.
# swift-format ships inside the Xcode toolchain (`xcrun swift-format`), so it
# is intentionally not listed.

brew "swiftlint"          # linting (bin/lint)
brew "xcbeautify"         # readable xcodebuild output (used by bin/* and CI)
brew "xcode-build-server" # feeds SourceKit-LSP so editors (Zed) get autocomplete

# The release .dmg is built with hdiutil, which ships with macOS, so no tool is needed.
