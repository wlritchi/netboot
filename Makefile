# netboot/Makefile

THIS := $(abspath $(lastword $(MAKEFILE_LIST)))
HERE := $(patsubst %/,%,$(dir $(THIS)))

GOCMD:=go
GOMODULECMD:=GO111MODULE=on go

# Local customizations to the above.
ifneq ($(wildcard Makefile.defaults),)
include Makefile.defaults
endif

all:
	$(error Please request a specific thing, there is no default target)

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

IPXE_BUILD_ARGS = EMBED=$(HERE)/pixiecore/boot.ipxe $(if $(BUILD_TIMESTAMP),BUILD_TIMESTAMP=$(BUILD_TIMESTAMP))

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
	$(if $(SOURCE_DATE_EPOCH),export SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) &&) \
	cd third_party && \
	. edk2/edksetup.sh && \
	build -a AARCH64 -t GCC -p edk2-platforms/Platform/RaspberryPi/RPi4/RPi4.dsc -b RELEASE
	@echo "Copying UEFI firmware to rpi4/bin/..."
	mkdir -p rpi4/bin
	cp third_party/Build/RPi4/RELEASE_GCC/FV/RPI_EFI.fd rpi4/bin/
	@echo "UEFI firmware build complete."
