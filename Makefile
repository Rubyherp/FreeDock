.PHONY: bundle run test clean release

bundle:
	./scripts/build.sh

run: bundle
	open build/FreeDock.app

test:
	swift test

release:
	./scripts/build.sh --release

clean:
	swift package clean
	rm -rf build/

format:
	swift format --recursive Sources Tests
