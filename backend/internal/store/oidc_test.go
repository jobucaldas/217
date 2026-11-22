package store

import (
	"sync"
	"testing"
)

func TestOIDCIdentityContract(t *testing.T) {
	for name, makeStore := range map[string]func(*testing.T) Store{
		"memory":   func(*testing.T) Store { return NewMemoryStore() },
		"postgres": func(t *testing.T) Store { return pgTestStore(t) },
	} {
		t.Run(name, func(t *testing.T) {
			s := makeStore(t)
			existing, err := s.CreateUser("oidc-existing@example.com", "Existing", "password")
			if err != nil {
				t.Fatal(err)
			}
			if _, err = s.LinkOIDCIdentity("issuer", "unverified", "oidc-existing@example.com", "", false); err == nil {
				t.Fatal("unverified email linked")
			}
			u, err := s.LinkOIDCIdentity("issuer", "subject", "oidc-existing@example.com", "", true)
			if err != nil || u.ID != existing.ID {
				t.Fatalf("verified link: %v", err)
			}
			if _, err = s.LinkOIDCIdentity("issuer", "subject", "changed@example.com", "", false); err != nil {
				t.Fatal(err)
			}
			other, err := s.LinkOIDCIdentity("issuer", "other", "oidc-other@example.com", "", false)
			if err != nil {
				t.Fatal(err)
			}
			if err = s.AttachOIDCIdentity(other.ID, "issuer", "subject"); err == nil {
				t.Fatal("moved linked identity")
			}
			if err = s.DeleteOIDCIdentity(existing.ID, "issuer"); err != nil {
				t.Fatal(err)
			}
			ids, err := s.OIDCIdentities(existing.ID)
			if err != nil || len(ids) != 0 {
				t.Fatalf("unlink: %v %v", ids, err)
			}
			if err = s.AttachOIDCIdentity(existing.ID, "issuer", "subject"); err != nil {
				t.Fatal(err)
			}
			if err = s.DeleteUser(existing.ID); err != nil {
				t.Fatal(err)
			}
			fresh, err := s.CreateUser("oidc-fresh@example.com", "Fresh", "password")
			if err != nil {
				t.Fatal(err)
			}
			if err = s.AttachOIDCIdentity(fresh.ID, "issuer", "subject"); err != nil {
				t.Fatal(err)
			}
			if err = s.SetPasswordCredential(fresh.ID, "hash"); err != nil {
				t.Fatal(err)
			}
			var wg sync.WaitGroup
			results := make(chan error, 2)
			for _, password := range []bool{true, false} {
				wg.Add(1)
				go func(password bool) {
					defer wg.Done()
					results <- s.RemoveSignInMethod(fresh.ID, "issuer", password, true, false)
				}(password)
			}
			wg.Wait()
			close(results)
			success := 0
			for err := range results {
				if err == nil {
					success++
				} else if err != ErrOnlySignInMethod {
					t.Fatal(err)
				}
			}
			if success != 1 {
				t.Fatalf("concurrent removals: %d succeeded", success)
			}
		})
	}
}
