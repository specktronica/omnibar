.PHONY: build run

APP := build/Omnibar.app

build:
	./scripts/build.sh

run: build
	-killall Omnibar
	open "$(APP)"
