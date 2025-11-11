package rpi4

import _ "embed"

// Embedded Raspberry Pi 4 boot files.
// These files are served via TFTP when a Raspberry Pi 4 boots over the network.

// ConfigTxt is the Raspberry Pi boot configuration file.
// It tells the Pi to boot in 64-bit mode and use RPI_EFI.fd as the UEFI firmware.
//
//go:embed config.txt
var ConfigTxt []byte

// RpiEfiFd is the UEFI firmware for Raspberry Pi 4.
// This is built from tianocore/edk2 for the RPi4 platform.
//
//go:embed bin/RPI_EFI.fd
var RpiEfiFd []byte

// Start4Elf is the GPU firmware for Raspberry Pi 4.
//
//go:embed bin/start4.elf
var Start4Elf []byte

// Fixup4Dat is the GPU firmware fixup file for Raspberry Pi 4.
//
//go:embed bin/fixup4.dat
var Fixup4Dat []byte

// BootcodeBin is the bootloader for older Raspberry Pi models.
// Pi 4 doesn't strictly need this, but some boot configurations may request it.
//
//go:embed bin/bootcode.bin
var BootcodeBin []byte

// Bcm2711Rpi4B is the device tree blob for Raspberry Pi 4 Model B.
//
//go:embed bin/bcm2711-rpi-4-b.dtb
var Bcm2711Rpi4B []byte

// Bcm2711Rpi400 is the device tree blob for Raspberry Pi 400.
//
//go:embed bin/bcm2711-rpi-400.dtb
var Bcm2711Rpi400 []byte

// Bcm2711RpiCm4 is the device tree blob for Raspberry Pi Compute Module 4.
//
//go:embed bin/bcm2711-rpi-cm4.dtb
var Bcm2711RpiCm4 []byte

// Files maps filenames to their embedded data.
// This is used by the TFTP server to serve files to the Raspberry Pi bootrom.
var Files = map[string][]byte{
	"config.txt":            ConfigTxt,
	"RPI_EFI.fd":            RpiEfiFd,
	"start4.elf":            Start4Elf,
	"fixup4.dat":            Fixup4Dat,
	"bootcode.bin":          BootcodeBin,
	"bcm2711-rpi-4-b.dtb":   Bcm2711Rpi4B,
	"bcm2711-rpi-400.dtb":   Bcm2711Rpi400,
	"bcm2711-rpi-cm4.dtb":   Bcm2711RpiCm4,
}
