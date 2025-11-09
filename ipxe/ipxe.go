package ipxe

import (
	_ "embed"
	"fmt"
	"strings"
)

//go:embed bin/ipxe.pxe
var ipxePxe []byte

//go:embed bin/undionly.kpxe
var undionly []byte

//go:embed bin/ipxe-x64.efi
var ipxeEfiX64 []byte

//go:embed bin/ipxe-i386.efi
var ipxeEfi32 []byte

//go:embed bin/snp-arm64.efi
var snpArm64 []byte

var assets = map[string][]byte{
	"third_party/ipxe/src/bin/ipxe.pxe":            ipxePxe,
	"third_party/ipxe/src/bin/undionly.kpxe":       undionly,
	"third_party/ipxe/src/bin-x86_64-efi/ipxe.efi": ipxeEfiX64,
	"third_party/ipxe/src/bin-i386-efi/ipxe.efi":   ipxeEfi32,
	"third_party/ipxe/src/bin-arm64-efi/snp.efi":   snpArm64,
}

// Asset loads and returns the asset for the given name.
// It returns an error if the asset could not be found.
func Asset(name string) ([]byte, error) {
	canonicalName := strings.Replace(name, "\\", "/", -1)
	if data, ok := assets[canonicalName]; ok {
		return data, nil
	}
	return nil, fmt.Errorf("Asset %s not found", name)
}

// MustAsset is like Asset but panics when Asset would return an error.
// It simplifies safe initialization of global variables.
func MustAsset(name string) []byte {
	data, err := Asset(name)
	if err != nil {
		panic("asset: Asset(" + name + "): " + err.Error())
	}
	return data
}
