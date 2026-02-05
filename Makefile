IMAGE_NAME := claude-desktop-appimage-builder
OUTPUT_DIR := $(CURDIR)/output

.PHONY: build image clean

build: image
	mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		-v $(CURDIR):/build/src:ro \
		-v $(OUTPUT_DIR):/build/output \
		$(IMAGE_NAME)

image:
	docker build -t $(IMAGE_NAME) docker/

clean:
	rm -rf $(OUTPUT_DIR)
