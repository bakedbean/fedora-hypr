IMAGE   ?= localhost/fedora-hypr
TAG     ?= $(shell sed -n 's#^FROM ghcr.io/ublue-os/base-main:\([0-9]*\).*#\1#p' Containerfile)
REMOTE  ?= ghcr.io/bakedbean/fedora-hypr
PODMAN  ?= podman

.PHONY: build shell check push vm test-migrate bump-base

# NOTIFY_SOCKET leaks from the Hyprland session (uwsm's compositor unit is Type=notify) into
# every terminal; crun then bind-mounts its directory into the build container and the
# package layer ships an empty /run/user/1000/systemd/notify (bootc lint warning).
build:
	env -u NOTIFY_SOCKET $(PODMAN) build -t $(IMAGE):$(TAG) .

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

# re-pin the Containerfile's FROM digests to what the tags resolve to now (CI does this weekly)
bump-base:
	tools/bump-base.sh
