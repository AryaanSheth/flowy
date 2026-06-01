APP_NAME := Flowy
VERSION  := 0.2.0
APP_BUNDLE := target/release/bundle/macos/$(APP_NAME).app
APPLICATIONS_BUNDLE := /Applications/$(APP_NAME).app

.PHONY: help doctor dev build dmg launch relaunch install install-relaunch install-relaunch-reset uninstall reset-accessibility open-installed check test logs clear-logs clean

help:
	@printf "Flowy targets:\n"
	@printf "  make doctor          Check the local Swift/macOS toolchain\n"
	@printf "  make dev             Build a debug native macOS app\n"
	@printf "  make build           Build the release native macOS app bundle\n"
	@printf "  make dmg             Build and package a distributable .dmg\n"
	@printf "  make launch          Open the packaged app from target/release\n"
	@printf "  make relaunch        Rebuild, kill old app, launch target app\n"
	@printf "  make install         Copy the packaged app to /Applications\n"
	@printf "  make install-relaunch Clean, rebuild, install, and launch /Applications app\n"
	@printf "  make install-relaunch-reset Same as install-relaunch, but reset Accessibility first\n"
	@printf "  make reset-accessibility Reset Flowy's Accessibility permission entry\n"
	@printf "  make open-installed  Open /Applications/flowy.app\n"
	@printf "  make check           Compile-check the native Swift app\n"
	@printf "  make test            Run native build smoke checks\n"
	@printf "  make logs            Tail Flowy's log file\n"
	@printf "  make clear-logs      Clear Flowy's log file\n"
	@printf "  make uninstall       Kill and remove /Applications/Flowy.app\n"
	@printf "  make clean           Remove native build artifacts\n"

doctor:
	./scripts/doctor-swift.sh

dev:
	./scripts/build-macos.sh --debug

build:
	./scripts/build-macos.sh

dmg: build
	./scripts/package-dmg.sh $(VERSION)

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

uninstall:
	pkill -x "$(APP_NAME)" 2>/dev/null || true
	rm -rf "$(APPLICATIONS_BUNDLE)"
	@printf "Uninstalled $(APP_NAME) from /Applications\n"

reset-accessibility:
	tccutil reset Accessibility com.flowy.app || true

open-installed:
	open "$(APPLICATIONS_BUNDLE)"

check:
	./scripts/build-macos.sh --debug --check-only

test:
	./scripts/build-macos.sh --debug --check-only
	/usr/bin/file "target/debug/bundle/macos/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" | grep -q "arm64"

logs:
	mkdir -p "$$HOME/Library/Logs/Flowy"
	touch "$$HOME/Library/Logs/Flowy/flowy.log"
	tail -n 200 -f "$$HOME/Library/Logs/Flowy/flowy.log"

clear-logs:
	mkdir -p "$$HOME/Library/Logs/Flowy"
	: > "$$HOME/Library/Logs/Flowy/flowy.log"

clean:
	rm -rf target .build
