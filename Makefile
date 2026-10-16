# Makeit-Markdown
#
# Linting always runs before a build so that the tree stays warning free.

SCHEME      := Makeit-markdown
PROJECT     := Makeit-markdown.xcodeproj
PACKAGE_DIR := Packages/MarkdownKit
PREFIX      ?= /usr/local
DESTINATION := platform=macOS

SAMPLES_DIR := Samples
SAMPLES_IN  := $(SAMPLES_DIR)/Input
SAMPLES_OUT := $(SAMPLES_DIR)/Output

SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)

# 'samples' must stay phony: macOS filesystems are case insensitive, so the
# Samples directory would otherwise satisfy the target and the rule never runs.
.PHONY: all lint lint-strict build test test-package test-app cli install-cli \
        samples clean help

all: lint build test

## Lint every Swift source file, reporting violations as warnings.
lint:
ifeq ($(SWIFTLINT),)
	@echo "warning: SwiftLint is not installed. Run 'brew install swiftlint'."
else
	@$(SWIFTLINT) lint --quiet
endif

## Lint and fail on any violation. Used in CI.
lint-strict:
ifeq ($(SWIFTLINT),)
	@echo "error: SwiftLint is not installed. Run 'brew install swiftlint'." && exit 1
else
	@$(SWIFTLINT) lint --quiet --strict
endif

## Build the app.
build: lint
	@xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-quiet

## Run every test: the package suite and the app suite.
test: test-package test-app

## Run the MarkdownKit and command line tests.
test-package: lint
	@cd $(PACKAGE_DIR) && swift test

## Run the app's unit tests.
test-app: lint
	@xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-quiet

## Build the command line tool in release configuration.
cli: lint
	@cd $(PACKAGE_DIR) && swift build -c release --product makeit-markdown
	@echo "Built $(PACKAGE_DIR)/.build/release/makeit-markdown"

## Install the command line tool into $(PREFIX)/bin.
install-cli: cli
	@install -d "$(PREFIX)/bin"
	@install -m 0755 "$(PACKAGE_DIR)/.build/release/makeit-markdown" "$(PREFIX)/bin/makeit-markdown"
	@echo "Installed $(PREFIX)/bin/makeit-markdown"

## Convert every document in Samples/Input for manual quality checks.
samples: cli
	@mkdir -p "$(SAMPLES_IN)" "$(SAMPLES_OUT)"
	@count=0; failed=0; \
	for file in "$(SAMPLES_IN)"/*; do \
		[ -f "$$file" ] || continue; \
		count=$$((count + 1)); \
		name=$$(basename "$$file"); \
		if "$(PACKAGE_DIR)/.build/release/makeit-markdown" "$$file" \
			--output "$(SAMPLES_OUT)" --overwrite \
			$(if $(EXPERIMENTAL),--experimental-tables,) >/dev/null; then \
			echo "  ok    $$name"; \
		else \
			echo "  FAIL  $$name"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	if [ "$$count" -eq 0 ]; then \
		echo "No documents found. Put some PDFs in $(SAMPLES_IN) and run again."; \
	else \
		echo "Converted $$((count - failed))/$$count into $(SAMPLES_OUT)"; \
	fi

## Remove all build products.
clean:
	@rm -rf $(PACKAGE_DIR)/.build DerivedData
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) -quiet || true

## List the available targets.
help:
	@grep -B1 '^[a-z-]*:' $(MAKEFILE_LIST) \
		| grep -A1 '^##' \
		| sed 's/^## //; s/:.*//' \
		| paste - - \
		| awk -F'\t' '{ printf "  \033[36m%-14s\033[0m %s\n", $$2, $$1 }'
