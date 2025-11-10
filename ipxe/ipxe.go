package ipxe

import _ "embed"

// Embedded iPXE firmware binaries for different architectures and boot modes.

// IpxePxe is the iPXE binary for chainloading from another iPXE instance.
//
//go:embed bin/ipxe.pxe
var IpxePxe []byte

// Undionly is the iPXE binary for x86 BIOS with PXE/UNDI support.
//
//go:embed bin/undionly.kpxe
var Undionly []byte

// IpxeEfiX64 is the iPXE binary for 64-bit x86 EFI systems.
//
//go:embed bin/ipxe-x64.efi
var IpxeEfiX64 []byte

// IpxeEfi32 is the iPXE binary for 32-bit x86 EFI systems.
//
//go:embed bin/ipxe-i386.efi
var IpxeEfi32 []byte

// SnpArm64 is the iPXE binary for 64-bit ARM EFI systems.
//
//go:embed bin/snp-arm64.efi
var SnpArm64 []byte
