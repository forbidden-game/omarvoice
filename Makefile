.PHONY: build build-swift build-python test test-swift test-python clean run

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
