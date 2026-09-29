# Build/publish helper for the bootc-fedora-ufficio image.
# Override on the command line, e.g.:
#   make build FEDORA_VERSION=45
#   make push ORG=my-org

# Single source of truth for the Fedora version: ARG FEDORA_VERSION in the
# Containerfile (override with `make build FEDORA_VERSION=X` for one-offs).
FEDORA_VERSION ?= $(shell sed -n 's/^ARG FEDORA_VERSION=//p' Containerfile)
IMAGE          ?= localhost/bootc-fedora-ufficio
INSTALLER_IMAGE ?= localhost/bootc-fedora-ufficio-installer
BUILDER_IMAGE  ?= ghcr.io/osbuild/image-builder-cli:latest
TAG            ?= latest
ORG            ?=
SHELLCHECK_IMAGE ?= docker.io/koalaman/shellcheck-alpine:v0.11.0

.PHONY: build lint shellcheck smoke push installer iso clean

# Build the image. `bootc container lint` runs at the end of the Containerfile,
# so a successful build already means the image is validated.
build:
	podman build --build-arg FEDORA_VERSION=$(FEDORA_VERSION) \
	    --build-arg "VERSION=$(FEDORA_VERSION)" \
	    --build-arg "SOURCE_COMMIT=$$(git rev-parse HEAD 2>/dev/null)" \
	    -t $(IMAGE):$(TAG) .

# Re-validate an already-built image. `build` already runs `bootc container lint`
# at the end of the Containerfile, so this is only for re-checking an existing
# image (e.g. one just pulled) without a full rebuild.
lint:
	podman run --rm $(IMAGE):$(TAG) bootc container lint

# Lint scripts without adding ShellCheck to the deployed operating system.
shellcheck:
	podman run --rm -v "$(CURDIR):/src:ro,Z" -w /src $(SHELLCHECK_IMAGE) shellcheck -s bash scripts/*.sh

# Check the custom operating-system content without requiring a VM boot.
smoke:
	podman run --rm $(IMAGE):$(TAG) bash -ceu 'bootc container lint; \
	    test -x /usr/libexec/bootc-ufficio/bootstrap-flatpaks.sh; \
	    test -x /usr/libexec/bootc-ufficio/bootstrap-python.sh; \
	    test -f /usr/lib/bootc/install/50-bootc-ufficio.toml; \
	    grep -Fxq "type = \"btrfs\"" /usr/lib/bootc/install/50-bootc-ufficio.toml; \
	    test -f /usr/lib/bootc/kargs.d/00-desktop.toml; \
	    grep -Fxq "kargs = [\"rhgb\", \"quiet\"]" /usr/lib/bootc/kargs.d/00-desktop.toml; \
	    readlink /etc/localtime | grep -Fxq /usr/share/zoneinfo/Europe/Rome; \
	    grep -Fxq LANG=it_IT.UTF-8 /etc/locale.conf; \
	    command -v firefox; \
	    rpm -q pcsc-lite opensc freeipa-client; \
	    systemctl is-enabled sshd >/dev/null 2>&1; \
	    test ! -e /usr/lib/infocamere_sign_desktop'

# Tag and push to ghcr.io via scripts/push.sh. Requires `podman login ghcr.io` once.
push:
	@test -n "$(ORG)" || { echo "usage: make push ORG=<your-org>"; exit 1; }
	./scripts/push.sh $(ORG) $(FEDORA_VERSION) $(IMAGE) $(TAG)

# Build the installer container (minimal Fedora base + Anaconda + ISO tools)
# used by image-builder. The office payload is NOT baked in: the kickstart
# (interactive-defaults.ks) pulls it from the registry at install time.
installer:
	podman build --build-arg FEDORA_VERSION=$(FEDORA_VERSION) \
	    -t $(INSTALLER_IMAGE):$(TAG) iso/
	# image-builder (target `iso`) gira rootful montando /var/lib/containers/storage:
	# importa l'immagine anche nello storage di root.
	bash -o pipefail -c 'podman save $(INSTALLER_IMAGE):$(TAG) | sudo podman load'

# Build the installer ISO using the official osbuild image-builder CONTAINER.
iso: installer
	mkdir -p output
	sudo podman run --privileged --rm --pull=newer \
	    --security-opt label=type:unconfined_t \
	    -v /var/lib/containers/storage:/var/lib/containers/storage \
	    -v "$(CURDIR)/output:/output" \
	    $(BUILDER_IMAGE) \
	    build --bootc-ref $(INSTALLER_IMAGE):$(TAG) \
	    --bootc-default-fs btrfs bootc-generic-iso

# Remove local build artifacts (ISO/qcow2 in output/). Does not remove images:
# reclaim those manually with `podman rmi` (rootless) / `sudo podman rmi` (root).
# `make iso` writes the ISO as root, so fall back to sudo if plain rm hits a
# root-owned file.
clean:
	rm -rf output 2>/dev/null || sudo rm -rf output
