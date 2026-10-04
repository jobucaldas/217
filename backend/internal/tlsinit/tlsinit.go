// Package tlsinit writes the certificates that encrypt traffic between the
// containers: a private CA and leaf certificates for PostgreSQL and the API.
// The CA key is discarded once the leaves are signed, so nothing else can be
// issued under it; certificates are reissued when one is missing or near expiry.
package tlsinit

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

const (
	validity    = 5 * 365 * 24 * time.Hour
	renewBefore = 30 * 24 * time.Hour
)

// PGHBA only lets PostgreSQL accept network connections over TLS. The local
// socket (the image's init scripts and health check) stays as the image has it.
const PGHBA = `# Written by 217 (server -init-tls): network connections must use TLS.
local   all  all        trust
hostssl all  all  all   scram-sha-256
`

// Service is one TLS server: its directory under the output dir, the host
// names clients use, and the uid that must own its key (-1 leaves it).
type Service struct {
	Name  string
	Hosts []string
	UID   int
}

// Ensure writes dir/ca.crt and dir/<service>/tls.{crt,key} unless current ones
// are already there. extra files (name -> content) go in each service dir.
func Ensure(dir string, services []Service, extra map[string]map[string]string, now time.Time) (bool, error) {
	for _, svc := range services {
		if len(svc.Hosts) == 0 {
			return false, fmt.Errorf("%s: at least one host name is required", svc.Name)
		}
	}
	if current(dir, services, now) {
		// Keep key ownership in step with the flags, e.g. after an image uid change.
		for _, svc := range services {
			if svc.UID >= 0 && os.Geteuid() == 0 {
				if err := os.Chown(filepath.Join(dir, svc.Name, "tls.key"), svc.UID, svc.UID); err != nil {
					return false, err
				}
			}
		}
		return false, writeExtra(dir, services, extra)
	}
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return false, err
	}
	caTmpl := &x509.Certificate{
		SerialNumber:          serial(),
		Subject:               pkix.Name{CommonName: "217 internal CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(validity),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLenZero:        true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey)
	if err != nil {
		return false, err
	}
	ca, err := x509.ParseCertificate(caDER)
	if err != nil {
		return false, err
	}
	for _, svc := range services {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			return false, err
		}
		tmpl := &x509.Certificate{
			SerialNumber: serial(),
			Subject:      pkix.Name{CommonName: svc.Hosts[0]},
			NotBefore:    now.Add(-time.Hour),
			NotAfter:     now.Add(validity),
			KeyUsage:     x509.KeyUsageDigitalSignature,
			ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		}
		for _, h := range svc.Hosts {
			if ip := net.ParseIP(h); ip != nil {
				tmpl.IPAddresses = append(tmpl.IPAddresses, ip)
			} else {
				tmpl.DNSNames = append(tmpl.DNSNames, h)
			}
		}
		der, err := x509.CreateCertificate(rand.Reader, tmpl, ca, &key.PublicKey, caKey)
		if err != nil {
			return false, err
		}
		keyDER, err := x509.MarshalPKCS8PrivateKey(key)
		if err != nil {
			return false, err
		}
		svcDir := filepath.Join(dir, svc.Name)
		if err := os.MkdirAll(svcDir, 0o755); err != nil {
			return false, err
		}
		if err := writeFile(filepath.Join(svcDir, "tls.key"), pemBlock("PRIVATE KEY", keyDER), 0o600, svc.UID); err != nil {
			return false, err
		}
		if err := writeFile(filepath.Join(svcDir, "tls.crt"), pemBlock("CERTIFICATE", der), 0o644, -1); err != nil {
			return false, err
		}
	}
	// The CA goes last: until it is written, current() keeps reissuing.
	if err := writeFile(filepath.Join(dir, "ca.crt"), pemBlock("CERTIFICATE", caDER), 0o644, -1); err != nil {
		return false, err
	}
	return true, writeExtra(dir, services, extra)
}

// current reports whether every leaf chains to dir/ca.crt, covers its hosts
// and stays valid past the renewal window.
func current(dir string, services []Service, now time.Time) bool {
	caPEM, err := os.ReadFile(filepath.Join(dir, "ca.crt"))
	if err != nil {
		return false
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(caPEM) {
		return false
	}
	for _, svc := range services {
		crtPEM, err := os.ReadFile(filepath.Join(dir, svc.Name, "tls.crt"))
		if err != nil {
			return false
		}
		if _, err := os.Stat(filepath.Join(dir, svc.Name, "tls.key")); err != nil {
			return false
		}
		block, _ := pem.Decode(crtPEM)
		if block == nil {
			return false
		}
		crt, err := x509.ParseCertificate(block.Bytes)
		if err != nil || now.Add(renewBefore).After(crt.NotAfter) {
			return false
		}
		for _, h := range svc.Hosts {
			if _, err := crt.Verify(x509.VerifyOptions{DNSName: h, Roots: roots, CurrentTime: now}); err != nil {
				return false
			}
		}
	}
	return true
}

func writeExtra(dir string, services []Service, extra map[string]map[string]string) error {
	for _, svc := range services {
		for name, content := range extra[svc.Name] {
			if err := writeFile(filepath.Join(dir, svc.Name, name), []byte(content), 0o644, -1); err != nil {
				return err
			}
		}
	}
	return nil
}

// writeFile replaces path atomically with the given mode and, when running as
// root, the given owner (PostgreSQL refuses a key it does not own).
func writeFile(path string, data []byte, mode os.FileMode, uid int) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	if uid >= 0 && os.Geteuid() == 0 {
		if err := os.Chown(tmp.Name(), uid, uid); err != nil {
			return fmt.Errorf("chown %s: %w", path, err)
		}
	}
	return os.Rename(tmp.Name(), path)
}

func pemBlock(kind string, der []byte) []byte {
	return pem.EncodeToMemory(&pem.Block{Type: kind, Bytes: der})
}

func serial() *big.Int {
	n, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 127))
	if err != nil {
		panic(err)
	}
	return n
}
