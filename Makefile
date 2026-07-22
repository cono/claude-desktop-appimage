IMAGE_NAME := claude-desktop-appimage-builder
OUTPUT_DIR := $(CURDIR)/output

.DEFAULT_GOAL := help
.PHONY: build image clean help install install-local uninstall update

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+%?:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: image ## Build the AppImage in Docker (output in ./output)
	mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		-v $(CURDIR):/build/src:ro \
		-v $(OUTPUT_DIR):/build/output \
		$(IMAGE_NAME)

image: ## Build the Docker builder image
	docker build -t $(IMAGE_NAME) docker/

clean: ## Remove the output directory
	rm -rf $(OUTPUT_DIR)

install: ## Install to /opt/claude from the latest GitHub release, with desktop integration
	bash scripts/install.sh

install-local: ## Build locally, then install that build to /opt/claude (for development)
	@ls $(OUTPUT_DIR)/claude-desktop-*.AppImage >/dev/null 2>&1 || $(MAKE) build
	bash scripts/install.sh --local

uninstall: ## Remove /opt/claude, the desktop entry, icon, and auto-update timer
	bash scripts/install.sh --uninstall

update: ## Update the installed Claude AppImage to the latest release now
	bash update.sh
