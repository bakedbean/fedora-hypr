IMAGE   ?= localhost/fedora-hypr
TAG     ?= $(shell sed -n 's/^FROM .*:\([0-9]*\)$$/\1/p' Containerfile)
REMOTE  ?= ghcr.io/bakedbean/fedora-hypr
PODMAN  ?= podman

.PHONY: build shell check push vm test-migrate

build:
	$(PODMAN) build -t $(IMAGE):$(TAG) .

shell: build
	$(PODMAN) run --rm -it $(IMAGE):$(TAG) bash

check: build
	$(PODMAN) run --rm -v ./tests:/tests:ro,z $(IMAGE):$(TAG) bash /tests/check.sh

push: build
	$(PODMAN) tag $(IMAGE):$(TAG) $(REMOTE):$(TAG)
	$(PODMAN) push $(REMOTE):$(TAG)

vm: build
	IMAGE=$(IMAGE):$(TAG) ./vm.sh

test-migrate:
	bash tests/migrate_test.sh
