IMAGE   ?= localhost/fedora-hypr
TAG     ?= 44
REMOTE  ?= ghcr.io/bakedbean/fedora-hypr
PODMAN  ?= podman

.PHONY: build shell check push

build:
	$(PODMAN) build -t $(IMAGE):$(TAG) .

shell: build
	$(PODMAN) run --rm -it $(IMAGE):$(TAG) bash

check: build
	$(PODMAN) run --rm -v ./tests:/tests:ro,z $(IMAGE):$(TAG) bash /tests/check.sh

push: build
	$(PODMAN) tag $(IMAGE):$(TAG) $(REMOTE):$(TAG)
	$(PODMAN) push $(REMOTE):$(TAG)
