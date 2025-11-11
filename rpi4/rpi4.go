package rpi4

import _ "embed"

// Embedded Raspberry Pi 4 UEFI firmware binary.

// RpiEfi is the UEFI firmware binary for Raspberry Pi 4.
// This is built from TianoCore EDK2 and provides a standards-compliant
// UEFI environment for network booting RPi4 devices.
//
//go:embed bin/RPI_EFI.fd
var RpiEfi []byte
