# netboot/Makefile

THIS := $(abspath $(lastword $(MAKEFILE_LIST)))
HERE := $(patsubst %/,%,$(dir $(THIS)))

GOCMD:=go
GOMODULECMD:=GO111MODULE=on go

# Docker image for cross-compilation builds
DOCKER_IMAGE ?= gcc:15

# Reproducible build timestamps
#
# These are calculated from git commit timestamps to ensure reproducible builds.
# Override with explicit values if needed (e.g., BUILD_TIMESTAMP=1234567890).

# iPXE timestamp: later of iPXE submodule commit or boot.ipxe modification
IPXE_SUBMODULE_TIMESTAMP := $(shell git -C third_party/ipxe log -1 --format=%ct 2>/dev/null || echo 0)
BOOT_IPXE_TIMESTAMP := $(shell git log -1 --format=%ct -- pixiecore/boot.ipxe 2>/dev/null || echo 0)
IPXE_BUILD_TIMESTAMP := $(shell \
	if [ $(IPXE_SUBMODULE_TIMESTAMP) -gt $(BOOT_IPXE_TIMESTAMP) ]; then \
		echo $(IPXE_SUBMODULE_TIMESTAMP); \
	else \
		echo $(BOOT_IPXE_TIMESTAMP); \
	fi)

# EDK2 timestamp: latest of edk2, edk2-platforms, and edk2-non-osi submodule commits
EDK2_TIMESTAMP := $(shell git -C third_party/edk2 log -1 --format=%ct 2>/dev/null || echo 0)
EDK2_PLATFORMS_TIMESTAMP := $(shell git -C third_party/edk2-platforms log -1 --format=%ct 2>/dev/null || echo 0)
EDK2_NONOSI_TIMESTAMP := $(shell git -C third_party/edk2-non-osi log -1 --format=%ct 2>/dev/null || echo 0)
EDK2_SOURCE_DATE_EPOCH := $(shell \
	max=$(EDK2_TIMESTAMP); \
	if [ $(EDK2_PLATFORMS_TIMESTAMP) -gt $$max ]; then max=$(EDK2_PLATFORMS_TIMESTAMP); fi; \
	if [ $(EDK2_NONOSI_TIMESTAMP) -gt $$max ]; then max=$(EDK2_NONOSI_TIMESTAMP); fi; \
	echo $$max)

# Allow overriding via command line or environment
BUILD_TIMESTAMP ?= $(IPXE_BUILD_TIMESTAMP)
SOURCE_DATE_EPOCH ?= $(EDK2_SOURCE_DATE_EPOCH)

# Print calculated timestamps (useful for CI to capture for commit messages)
.PHONY: print-timestamps
print-timestamps:
	@echo "BUILD_TIMESTAMP=$(BUILD_TIMESTAMP)"
	@echo "SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)"

# Local customizations to the above.
ifneq ($(wildcard Makefile.defaults),)
include Makefile.defaults
endif

all:
	$(error Please request a specific thing, there is no default target)

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning EDK2 BaseTools..."
	-$(MAKE) -C third_party/edk2/BaseTools clean 2>/dev/null || true
	@echo "Cleaning iPXE build artifacts..."
	-$(MAKE) -C third_party/ipxe/src clean 2>/dev/null || true
	@echo "Cleaning EDK2 Build directory..."
	rm -rf third_party/Build
	@echo "Clean complete."

.PHONY: clean-ipxe
clean-ipxe:
	-$(MAKE) -C third_party/ipxe/src clean 2>/dev/null || true

.PHONY: clean-edk2
clean-edk2:
	-$(MAKE) -C third_party/edk2/BaseTools clean 2>/dev/null || true
	rm -rf third_party/Build

.PHONY: ci-prepare
ci-prepare:
	$(GOCMD) get -u github.com/estesp/manifest-tool

.PHONY: build
build:
	$(GOMODULECMD) install -v ./cmd/pixiecore

.PHONY: test
test:
	$(GOMODULECMD) test ./...
	$(GOMODULECMD) test -race ./...

.PHONY: lint
lint:
	$(GOMODULECMD) tool vet .

REGISTRY=pixiecore
TAG=dev
.PHONY: ci-push-images
ci-push-images:
	make -f Makefile.inc push GOARCH=amd64   TAG=$(TAG)-amd64   BINARY=pixiecore REGISTRY=$(REGISTRY)
	make -f Makefile.inc push GOARCH=arm     TAG=$(TAG)-arm     BINARY=pixiecore REGISTRY=$(REGISTRY)
	make -f Makefile.inc push GOARCH=arm64   TAG=$(TAG)-arm64   BINARY=pixiecore REGISTRY=$(REGISTRY)
	make -f Makefile.inc push GOARCH=ppc64le TAG=$(TAG)-ppc64le BINARY=pixiecore REGISTRY=$(REGISTRY)
	make -f Makefile.inc push GOARCH=s390x   TAG=$(TAG)-s390x   BINARY=pixiecore REGISTRY=$(REGISTRY)
	manifest-tool push from-args --platforms linux/amd64,linux/arm,linux/arm64,linux/ppc64le,linux/s390x --template $(REGISTRY)/pixiecore:$(TAG)-ARCH --target $(REGISTRY)/pixiecore:$(TAG)

.PHONY: ci-config
ci-config:
	(cd .circleci && go run gen-config.go >config.yml)

IPXE_BUILD_ARGS = EMBED=$(HERE)/pixiecore/boot.ipxe BUILD_TIMESTAMP=$(BUILD_TIMESTAMP)

.PHONY: update-ipxe
update-ipxe:
	$(MAKE) -C third_party/ipxe/src \
	$(IPXE_BUILD_ARGS) \
	bin/ipxe.pxe \
	bin/undionly.kpxe \
	bin-x86_64-efi/ipxe.efi \
	bin-i386-efi/ipxe.efi
	$(MAKE) -C third_party/ipxe/src \
	CROSS=aarch64-linux-gnu- \
	$(IPXE_BUILD_ARGS) \
	bin-arm64-efi/snp.efi
	mkdir -p ipxe/bin
	cp third_party/ipxe/src/bin/ipxe.pxe ipxe/bin/
	cp third_party/ipxe/src/bin/undionly.kpxe ipxe/bin/
	cp third_party/ipxe/src/bin-x86_64-efi/ipxe.efi ipxe/bin/ipxe-x64.efi
	cp third_party/ipxe/src/bin-i386-efi/ipxe.efi ipxe/bin/ipxe-i386.efi
	cp third_party/ipxe/src/bin-arm64-efi/snp.efi ipxe/bin/snp-arm64.efi

# Raspberry Pi 4 firmware update target
#
# Downloads the latest stable Raspberry Pi firmware binaries (GPU firmware,
# device tree blobs, etc.) and copies them to rpi4/bin/ for commit.
#
# We download a GitHub archive instead of using a git submodule because the
# raspberrypi/firmware repository is huge (>1GB) and we only need a handful
# of small files from it. This keeps clone times reasonable.
#
# Run this target when you want to update to the latest firmware and commit
# the changes. A GitHub Actions workflow can run this periodically to check
# for updates.
.PHONY: update-rpi4-firmware
update-rpi4-firmware:
	@echo "Downloading latest Raspberry Pi firmware from stable branch..."
	@rm -rf third_party/rpi-firmware third_party/rpi-firmware-tmp third_party/rpi-firmware.tar.gz
	@mkdir -p third_party/rpi-firmware-tmp
	wget -O third_party/rpi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/refs/heads/stable.tar.gz
	tar -xzf third_party/rpi-firmware.tar.gz -C third_party/rpi-firmware-tmp --strip-components=2 firmware-stable/boot
	mv third_party/rpi-firmware-tmp third_party/rpi-firmware
	rm -f third_party/rpi-firmware.tar.gz
	@echo "Copying firmware files to rpi4/bin/ for commit..."
	mkdir -p rpi4/bin
	cp third_party/rpi-firmware/start4.elf rpi4/bin/
	cp third_party/rpi-firmware/fixup4.dat rpi4/bin/
	cp third_party/rpi-firmware/bootcode.bin rpi4/bin/
	cp third_party/rpi-firmware/bcm2711-rpi-4-b.dtb rpi4/bin/
	cp third_party/rpi-firmware/bcm2711-rpi-400.dtb rpi4/bin/
	cp third_party/rpi-firmware/bcm2711-rpi-cm4.dtb rpi4/bin/
	@echo "Firmware update complete. Review changes with 'git diff rpi4/bin/' and commit if desired."

# Raspberry Pi 4 UEFI firmware build target
#
# Builds RPI_EFI.fd from TianoCore EDK2 sources. This is the UEFI firmware
# that runs on the Pi after the GPU firmware loads it.
#
# This is independent of the Pi firmware files (start4.elf, etc.) - those are
# updated separately via update-rpi4-firmware.
.PHONY: update-rpi4
update-rpi4:
	@echo "Building EDK2 BaseTools..."
	cd third_party/edk2 && \
	. ./edksetup.sh && \
	$(MAKE) -C BaseTools
	@echo "Building RPi4 UEFI firmware (RPI_EFI.fd)..."
	export GCC_AARCH64_PREFIX=aarch64-linux-gnu- && \
	export WORKSPACE=$(HERE)/third_party && \
	export PACKAGES_PATH=$(HERE)/third_party/edk2:$(HERE)/third_party/edk2-platforms:$(HERE)/third_party/edk2-non-osi && \
	export SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) && \
	cd third_party && \
	. edk2/edksetup.sh && \
	build -a AARCH64 -t GCC -p edk2-platforms/Platform/RaspberryPi/RPi4/RPi4.dsc -b RELEASE
	@echo "Copying UEFI firmware to rpi4/bin/..."
	mkdir -p rpi4/bin
	cp third_party/Build/RPi4/RELEASE_GCC/FV/RPI_EFI.fd rpi4/bin/
	@echo "UEFI firmware build complete."

# Docker-based build targets
#
# These targets run the builds inside a Docker container for reproducibility.
# They handle:
# - Installing cross-compilation toolchains
# - Configuring git safe directories
# - Cleaning stale build artifacts that may have host-specific paths
# - Running the actual build
# - Fixing file ownership after the build
#
# Use BUILD_TIMESTAMP and SOURCE_DATE_EPOCH for reproducible builds.

DOCKER_RUN = docker run --rm -v $(HERE):/netboot -w /netboot $(DOCKER_IMAGE)
DOCKER_GIT_SAFE_DIRS = \
	git config --global --add safe.directory /netboot && \
	git config --global --add safe.directory /netboot/third_party/ipxe && \
	git config --global --add safe.directory /netboot/third_party/edk2 && \
	git config --global --add safe.directory /netboot/third_party/edk2-platforms && \
	git config --global --add safe.directory /netboot/third_party/edk2-non-osi

.PHONY: docker-update-ipxe
docker-update-ipxe:
	@echo "Using BUILD_TIMESTAMP=$(BUILD_TIMESTAMP)"
	$(DOCKER_RUN) bash -c '\
		apt-get update && apt-get install -y crossbuild-essential-arm64 && \
		$(DOCKER_GIT_SAFE_DIRS) && \
		$(MAKE) clean-ipxe && \
		$(MAKE) update-ipxe BUILD_TIMESTAMP=$(BUILD_TIMESTAMP)'
	@echo "Fixing file ownership..."
	@if [ -n "$$SUDO_UID" ]; then \
		chown -R $$SUDO_UID:$$SUDO_GID $(HERE)/ipxe/bin $(HERE)/third_party/ipxe/src; \
	elif [ $$(id -u) -eq 0 ]; then \
		echo "Warning: Running as root without SUDO_UID set, skipping chown"; \
	fi

.PHONY: docker-update-rpi4
docker-update-rpi4:
	@echo "Using SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)"
	$(DOCKER_RUN) bash -c '\
		apt-get update && apt-get install -y python3 python-is-python3 uuid-dev crossbuild-essential-arm64 acpica-tools && \
		$(DOCKER_GIT_SAFE_DIRS) && \
		$(MAKE) clean-edk2 && \
		$(MAKE) update-rpi4 SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)'
	@echo "Fixing file ownership..."
	@if [ -n "$$SUDO_UID" ]; then \
		chown -R $$SUDO_UID:$$SUDO_GID $(HERE)/rpi4/bin $(HERE)/third_party/Build $(HERE)/third_party/edk2/BaseTools; \
	elif [ $$(id -u) -eq 0 ]; then \
		echo "Warning: Running as root without SUDO_UID set, skipping chown"; \
	fi

.PHONY: docker-clean
docker-clean:
	$(DOCKER_RUN) $(MAKE) clean
