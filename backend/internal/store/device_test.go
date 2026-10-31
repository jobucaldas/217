package store

import (
	"testing"
	"time"

	"217/backend/internal/model"
)

func TestDeviceKeysChallengeOnceAndRevokeWithLogout(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		u, err := s.LinkWorkOSIdentity("device-"+name, "device-"+name+"@example.com", "D", true)
		if err != nil {
			t.Fatal(err)
		}
		keyID, err := s.CreateDeviceKey(u.ID, []byte("pkix"))
		if err != nil {
			t.Fatal(err)
		}
		if err := s.SetDeviceChallenge(keyID, "c1", time.Now().Add(time.Minute)); err != nil {
			t.Fatal(err)
		}
		if _, _, err := s.ConsumeDeviceChallenge(keyID, "wrong"); err == nil {
			t.Fatal("wrong challenge accepted")
		}
		// The failed try used the challenge up.
		if _, _, err := s.ConsumeDeviceChallenge(keyID, "c1"); err == nil {
			t.Fatal("challenge reused after a failed try")
		}
		_ = s.SetDeviceChallenge(keyID, "c2", time.Now().Add(time.Minute))
		owner, pub, err := s.ConsumeDeviceChallenge(keyID, "c2")
		if err != nil || owner != u.ID || string(pub) != "pkix" {
			t.Fatalf("consume: %q %q %v", owner, pub, err)
		}
		if err := s.CreateDeviceSession(u.ID, keyID, "tok-"+name, time.Now().Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
		if _, err := s.GetUserBySession("tok-" + name); err != nil {
			t.Fatal(err)
		}
		if keys, _ := s.ListDeviceKeys(u.ID); len(keys) != 1 || keys[0].ID != keyID {
			t.Fatalf("list: %#v", keys)
		}
		if err := s.DeleteSessionAndDevice("tok-" + name); err != nil {
			t.Fatal(err)
		}
		if err := s.SetDeviceChallenge(keyID, "c3", time.Now().Add(time.Minute)); err == nil {
			t.Fatal("key survived logout")
		}
		if keys, _ := s.ListDeviceKeys(u.ID); len(keys) != 0 {
			t.Fatalf("keys after logout: %#v", keys)
		}
	})
}

func TestDeviceKeysAreCappedPerUser(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		u, _ := s.LinkWorkOSIdentity("cap-"+name, "cap-"+name+"@example.com", "C", true)
		var last string
		for i := 0; i < model.MaxDeviceKeysPerUser+2; i++ {
			last, _ = s.CreateDeviceKey(u.ID, []byte("k"))
		}
		keys, _ := s.ListDeviceKeys(u.ID)
		found := false
		for _, k := range keys {
			found = found || k.ID == last
		}
		if len(keys) != model.MaxDeviceKeysPerUser || !found {
			t.Fatalf("%d keys, newest kept: %v", len(keys), found)
		}
	})
}
