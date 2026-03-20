.PHONY: build build-swift build-python test test-swift test-python clean run dist app sign notarize dmg

VERSION := $(shell sed -n 's/^__version__ = "\(.*\)"/\1/p' src/ohmyvoice/__init__.py)

build: build-swift

build-swift:
	cd ui && swift build -c release

build-python:
	pip install -e ".[dev]"

test: test-swift test-python

test-swift:
	cd ui && swift test

test-python:
	python -m pytest tests/test_ui_bridge.py tests/test_settings_reload.py -v

clean:
	cd ui && swift package clean
	rm -rf ui/.build

run: build-swift
	python -m ohmyvoice

dist: build-swift
	pyinstaller ohmyvoice.spec --noconfirm
	mkdir -p dist/OhMyVoice.app/Contents/Resources
	cp -R resources/icons dist/OhMyVoice.app/Contents/Resources/icons
	cp -R resources/sounds dist/OhMyVoice.app/Contents/Resources/sounds 2>/dev/null || true
	cp resources/AppIcon.icns dist/OhMyVoice.app/Contents/Resources/AppIcon.icns 2>/dev/null || true
	cp ui/.build/release/ohmyvoice-ui dist/OhMyVoice.app/Contents/MacOS/
	@# mlx Metal shaders are not picked up by PyInstaller — copy manually
	cp .venv/lib/python3.13/site-packages/mlx/lib/mlx.metallib \
		dist/OhMyVoice.app/Contents/Frameworks/mlx/lib/

app: dist

sign:
	@# inside-out signing: Frameworks/ Mach-O → Swift binary → Python binary → outer bundle
	find dist/OhMyVoice.app/Contents/Frameworks -type f \( -name '*.dylib' -o -name '*.so' -o -perm +111 \) -exec sh -c \
		'file "$$1" | grep -q "Mach-O" && codesign --force --options runtime --sign "$(DEVELOPER_ID_APPLICATION)" "$$1"' _ {} \;
	codesign --force --options runtime --sign "$(DEVELOPER_ID_APPLICATION)" \
		dist/OhMyVoice.app/Contents/MacOS/ohmyvoice-ui
	codesign --force --options runtime --sign "$(DEVELOPER_ID_APPLICATION)" \
		--entitlements entitlements.plist dist/OhMyVoice.app/Contents/MacOS/ohmyvoice
	codesign --force --options runtime --sign "$(DEVELOPER_ID_APPLICATION)" \
		--entitlements entitlements.plist dist/OhMyVoice.app

notarize:
	ditto -c -k --keepParent dist/OhMyVoice.app dist/OhMyVoice.zip
	xcrun notarytool submit dist/OhMyVoice.zip \
		--apple-id "$(APPLE_ID)" --team-id "$(APPLE_TEAM_ID)" \
		--password "$(APP_PASSWORD)" --wait
	rm dist/OhMyVoice.zip
	xcrun stapler staple dist/OhMyVoice.app

dmg: dist sign notarize
	rm -f dist/OhMyVoice-$(VERSION)-arm64.dmg
	create-dmg --volname OhMyVoice --window-size 600 400 \
		--icon-size 128 --icon OhMyVoice.app 150 200 \
		--app-drop-link 450 200 \
		dist/OhMyVoice-$(VERSION)-arm64.dmg dist/OhMyVoice.app
	codesign --sign "$(DEVELOPER_ID_APPLICATION)" dist/OhMyVoice-$(VERSION)-arm64.dmg
	xcrun notarytool submit dist/OhMyVoice-$(VERSION)-arm64.dmg \
		--apple-id "$(APPLE_ID)" --team-id "$(APPLE_TEAM_ID)" \
		--password "$(APP_PASSWORD)" --wait
	xcrun stapler staple dist/OhMyVoice-$(VERSION)-arm64.dmg
