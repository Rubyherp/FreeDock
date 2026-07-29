.PHONY: bundle run test clean release

bundle:
	./scripts/build.sh

run: bundle
	@killall FreeDock >/dev/null 2>&1 || true
	@sleep 0.5
	@open -n "$(CURDIR)/build/FreeDock.app"

test:
	swift test

release:
	./scripts/build.sh --release

clean:
	swift package clean
	rm -rf build/

format:
	swift format --recursive Sources Tests
