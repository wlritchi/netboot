// Copyright 2016 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package pixiecore

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"path/filepath"
	"strconv"
	"strings"

	"go.universe.tf/netboot/rpi4"
	"go.universe.tf/netboot/tftp"
)

func (s *Server) serveTFTP(l net.PacketConn) error {
	ts := tftp.Server{
		Handler:     s.handleTFTP,
		InfoLog:     func(msg string) { s.debug("TFTP", msg) },
		TransferLog: s.logTFTPTransfer,
	}
	err := ts.Serve(l)
	if err != nil {
		return fmt.Errorf("TFTP server shut down: %s", err)
	}
	return nil
}

func extractInfo(path string) (net.HardwareAddr, int, error) {
	pathElements := strings.Split(path, "/")
	if len(pathElements) != 2 {
		return nil, 0, errors.New("not found")
	}

	mac, err := net.ParseMAC(pathElements[0])
	if err != nil {
		return nil, 0, fmt.Errorf("invalid MAC address %q", pathElements[0])
	}

	i, err := strconv.Atoi(pathElements[1])
	if err != nil {
		return nil, 0, errors.New("not found")
	}

	return mac, i, nil
}

func (s *Server) logTFTPTransfer(clientAddr net.Addr, path string, err error) {
	mac, _, pathErr := extractInfo(path)
	if pathErr != nil {
		// Not a Pixiecore path, might be a Raspberry Pi boot file request
		filename := filepath.Base(path)
		if err != nil {
			s.log("TFTP", "Send of %q to %s failed: %s", path, clientAddr, err)
		} else {
			s.log("TFTP", "Sent %q to %s", filename, clientAddr)
		}
		return
	}
	if err != nil {
		s.log("TFTP", "Send of %q to %s failed: %s", path, clientAddr, err)
	} else {
		s.log("TFTP", "Sent %q to %s", path, clientAddr)
		s.machineEvent(mac, machineStateTFTP, "Sent iPXE to %s", clientAddr)
	}
}

func (s *Server) handleTFTP(path string, clientAddr net.Addr) (io.ReadCloser, int64, error) {
	// Try to parse as Pixiecore path (MAC/firmware_type) first
	_, i, err := extractInfo(path)
	if err == nil {
		// It's a Pixiecore path, serve iPXE binary
		bs, ok := s.Ipxe[Firmware(i)]
		if !ok {
			return nil, 0, fmt.Errorf("unknown firmware type %d", i)
		}
		return ioutil.NopCloser(bytes.NewBuffer(bs)), int64(len(bs)), nil
	}

	// Not a Pixiecore path, try serving as Raspberry Pi boot file
	// The Pi bootrom requests files by name (possibly with a directory prefix)
	// Strip any directory prefix to get just the filename
	filename := filepath.Base(path)

	// Special case: Pi UEFI firmware may request bootaa64.efi from efi/boot/ directory
	// This should be served from the ipxe package as the ARM64 iPXE binary
	if filename == "bootaa64.efi" {
		if bs, ok := s.Ipxe[FirmwareARM64EFI]; ok {
			return ioutil.NopCloser(bytes.NewBuffer(bs)), int64(len(bs)), nil
		}
	}

	// Look up the file in the RPi4 embedded files
	bs, ok := rpi4.Files[filename]
	if !ok {
		return nil, 0, fmt.Errorf("unknown file %q", filename)
	}

	return ioutil.NopCloser(bytes.NewBuffer(bs)), int64(len(bs)), nil
}
