BIN_DIR ?= $(HOME)/.local/bin
BINARY = alfy-clean

.PHONY: build install

build:
	swift build -c release

install: build
	install -d $(BIN_DIR)
	install -m 755 .build/release/$(BINARY) $(BIN_DIR)/$(BINARY)
