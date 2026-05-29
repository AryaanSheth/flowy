APP_NAME := Flowey
APP_BUNDLE := target/release/bundle/macos/$(APP_NAME).app
APPLICATIONS_BUNDLE := /Applications/$(APP_NAME).app

.PHONY: help doctor dev build launch relaunch install install-relaunch install-relaunch-reset reset-accessibility open-installed check test clean

help:
	@printf "Flowey targets:\n"
	@printf "  make doctor          Check the local Swift/macOS toolchain\n"
	@printf "  make dev             Build a debug native macOS app\n"
	@printf "  make build           Build the release native macOS app bundle\n"
	@printf "  make launch          Open the packaged app from target/release\n"
	@printf "  make relaunch        Rebuild, kill old app, launch target app\n"
	@printf "  make install         Copy the packaged app to /Applications\n"
	@printf "  make install-relaunch Clean, rebuild, install, and launch /Applications app\n"
	@printf "  make install-relaunch-reset Same as install-relaunch, but reset Accessibility first\n"
	@printf "  make reset-accessibility Reset Flowey's Accessibility permission entry\n"
	@printf "  make open-installed  Open /Applications/flowey.app\n"
	@printf "  make check           Compile-check the native Swift app\n"
	@printf "  make test            Run native build smoke checks\n"
	@printf "  make clean           Remove native build artifacts\n"

doctor:
	./scripts/doctor-swift.sh

dev:
	./scripts/build-macos.sh --debug

build:
	./scripts/build-macos.sh

launch: build
	open "$(APP_BUNDLE)"

relaunch:
	./scripts/rebuild-launch.sh

install: build
	rm -rf "$(APPLICATIONS_BUNDLE)"
	cp -R "$(APP_BUNDLE)" /Applications/

install-relaunch:
	./scripts/rebuild-launch.sh --install

install-relaunch-reset:
	./scripts/rebuild-launch.sh --install --reset-accessibility

reset-accessibility:
	tccutil reset Accessibility com.flowey.app || true

open-installed:
	open "$(APPLICATIONS_BUNDLE)"

check:
	./scripts/build-macos.sh --debug --check-only

test:
	./scripts/build-macos.sh --debug --check-only
	/usr/bin/file "target/debug/bundle/macos/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" | grep -q "arm64"

clean:
	rm -rf target .build
