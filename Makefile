IMAGE_NAME := claude-desktop-appimage-builder
OUTPUT_DIR := $(CURDIR)/output

.DEFAULT_GOAL := help
.PHONY: build image clean help

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
