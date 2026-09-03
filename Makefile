.PHONY: build run release

APP := build/Omnibar.app

build:
	./scripts/build.sh

run: build
	-killall Omnibar
	open "$(APP)"

# Developer ID sign, notarize, staple, zip to build/Omnibar-<version>.zip
release:
	./scripts/package.sh
