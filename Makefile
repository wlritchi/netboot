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

.PHONY: update-rpi4
update-rpi4:
	# Set up EDK2 build environment
	cd third_party/edk2 && \
	. ./edksetup.sh && \
	$(MAKE) -C BaseTools
	# Build RPi4 UEFI firmware
	export GCC_AARCH64_PREFIX=aarch64-linux-gnu- && \
	export WORKSPACE=$(HERE)/third_party && \
	export PACKAGES_PATH=$(HERE)/third_party/edk2:$(HERE)/third_party/edk2-platforms:$(HERE)/third_party/edk2-non-osi && \
	$(if $(SOURCE_DATE_EPOCH),export SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) &&) \
	cd third_party && \
	. edk2/edksetup.sh && \
	build -a AARCH64 -t GCC -p edk2-platforms/Platform/RaspberryPi/RPi4/RPi4.dsc -b RELEASE
	# Copy built firmware to rpi4/bin
	mkdir -p rpi4/bin
	cp third_party/Build/RPi4/RELEASE_GCC/FV/RPI_EFI.fd rpi4/bin/
