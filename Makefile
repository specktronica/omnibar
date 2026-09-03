.PHONY: build run release publish remove

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

# Quit, restore Dock, remove Applications copies, Homebrew cask/tap, prefs, TCC.
remove:
	./scripts/remove.sh
