SHELL := /bin/bash

.PHONY: build test acceptance lint format app release

build:
	swift build

# Swift Testing, in parallel: every test makes its own temp folder and fakes.
test:
	swift test --parallel

# The bash script's bats suite against the binary, then both side by side on a
# fake home. Needs DOTFILES pointing at a checkout of the dotfiles repository.
acceptance:
	./Scripts/bats.sh
	RUN=1 ./Scripts/compare.sh

lint:
	./Scripts/lint.sh lint

format:
	./Scripts/lint.sh format

app:
	./Scripts/package_app.sh release

release:
	./Scripts/build_release.sh
