FORMAT_PATHS := Mothball MothballTests

.PHONY: generate
generate:
	xcodegen generate --quiet

.PHONY: format
format:
	swift format --recursive --in-place $(FORMAT_PATHS)

.PHONY: lint
lint:
	swift format lint --recursive --strict $(FORMAT_PATHS)
	shellcheck scripts/*.sh

.PHONY: build
build: generate
	xcodebuild -project Mothball.xcodeproj -scheme Mothball -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGNING_ALLOWED=NO build

.PHONY: test
test: generate
	./scripts/test.sh

# Runs the round-trip spike on a simulator and prints the report. Override the device with
# IOS_SIM="iPhone 16 Pro".
.PHONY: spike-sim
spike-sim: generate
	./scripts/spike-sim.sh

# Re-renders the app icon PNGs from design/icon/*.svg after an edit. Needs rsvg-convert.
.PHONY: app-icon
app-icon:
	./scripts/app-icon.sh

.PHONY: clean
clean:
	rm -rf Mothball.xcodeproj Mothball/Info.plist Mothball/Mothball.entitlements
