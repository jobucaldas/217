package tlsinit

import (
	"crypto/tls"
	"crypto/x509"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestEnsureIssuesVerifiableCertsOnceAndRenews(t *testing.T) {
	dir := t.TempDir()
	services := []Service{{Name: "backend", Hosts: []string{"backend", "localhost"}, UID: -1}}
	extra := map[string]map[string]string{"backend": {"note.txt": "hi"}}
	now := time.Now()

	issued, err := Ensure(dir, services, extra, now)
	if err != nil || !issued {
		t.Fatalf("first Ensure = %v, %v", issued, err)
	}
	if b, err := os.ReadFile(filepath.Join(dir, "backend", "note.txt")); err != nil || string(b) != "hi" {
		t.Fatalf("extra file: %q %v", b, err)
	}
	info, err := os.Stat(filepath.Join(dir, "backend", "tls.key"))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("key mode: %v %v", info.Mode(), err)
	}
	if issued, err := Ensure(dir, services, extra, now); err != nil || issued {
		t.Fatalf("second Ensure reissued: %v %v", issued, err)
	}

	// A client trusting only ca.crt reaches the service by its host name.
	cert, err := tls.LoadX509KeyPair(filepath.Join(dir, "backend", "tls.crt"), filepath.Join(dir, "backend", "tls.key"))
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("ok")) }))
	srv.TLS = &tls.Config{Certificates: []tls.Certificate{cert}}
	srv.StartTLS()
	defer srv.Close()
	caPEM, _ := os.ReadFile(filepath.Join(dir, "ca.crt"))
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(caPEM)
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: "backend"}}}
	resp, err := client.Get(srv.URL)
	if err != nil {
		t.Fatalf("TLS to issued cert: %v", err)
	}
	resp.Body.Close()

	wrongName := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: "postgres"}}}
	if _, err := wrongName.Get(srv.URL); err == nil {
		t.Fatal("certificate accepted for a host it was not issued to")
	}

	if issued, err := Ensure(dir, services, extra, now.Add(validity-renewBefore/2)); err != nil || !issued {
		t.Fatalf("near expiry not renewed: %v %v", issued, err)
	}
}
