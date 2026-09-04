.PHONY: build run release publish brew-install remove

APP := build/Omnibar.app

build:
	./scripts/build.sh

run: build
	-killall Omnibar
	open "$(APP)"

# Developer ID sign, notarize, staple, zip to build/Omnibar-<version>.zip
release:
	./scripts/package.sh

# GitHub Release on v<version> + bump specktronica/homebrew-omnibar.
# Needs build/Omnibar-<version>.zip from `make release`.
publish:
	./scripts/publish.sh

# Install or upgrade the Homebrew cask (specktronica/omnibar/omnibar).
brew-install:
	command -v brew >/dev/null 2>&1 || { echo "Homebrew is required (https://brew.sh)." >&2; exit 1; }
	if brew list --cask omnibar >/dev/null 2>&1; then \
	  brew upgrade --cask specktronica/omnibar/omnibar; \
	else \
	  brew install --cask specktronica/omnibar/omnibar; \
	fi

# Quit, restore Dock, remove Applications copies, Homebrew cask/tap, prefs, TCC.
remove:
	./scripts/remove.sh
