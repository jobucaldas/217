package store

import (
	"testing"
	"time"

	"217/backend/internal/model"
)

func TestShareInviteAcceptRevokeAndInbox(t *testing.T) {
	s := NewMemoryStore()
	owner, err := s.CreateUser("girl@example.com", "Girl", "password123")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.SetRole(owner.ID, "owner"); err != nil {
		t.Fatal(err)
	}
	partner, err := s.CreateUser("bf@example.com", "Boyfriend", "password123")
	if err != nil {
		t.Fatal(err)
	}

	enabled, err := s.EnableShare(owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if enabled.Status != model.ShareOpen || enabled.InviteCode == "" || !enabled.CanEditCalendar {
		t.Fatalf("unexpected enable state: %+v", enabled)
	}

	accepted, err := s.AcceptShare(partner.ID, enabled.InviteCode)
	if err != nil {
		t.Fatal(err)
	}
	if accepted.Status != model.ShareActive || accepted.OwnerName != "Girl" {
		t.Fatalf("unexpected accept state: %+v", accepted)
	}
	partnerReload, err := s.GetUserByID(partner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if partnerReload.Role != model.RolePartner {
		t.Fatalf("expected partner role, got %q", partnerReload.Role)
	}

	subject, err := s.CalendarSubjectID(partner.ID)
	if err != nil || subject != owner.ID {
		t.Fatalf("partner calendar subject=%q err=%v", subject, err)
	}

	if _, err := s.UpsertEntry(owner.ID, "2026-10-01", model.UpsertRequest{Taken: model.BoolPtr(true)}); err != nil {
		t.Fatal(err)
	}
	entries, err := s.ListEntries(subject, 2026, 10)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected owner entries via partner subject, got %d err=%v", len(entries), err)
	}

	note, err := s.CreatePartnerNote(partner.ID, "thinking of you")
	if err != nil {
		t.Fatal(err)
	}
	inbox, err := s.ListInboxNotes(owner.ID)
	if err != nil || len(inbox) != 1 || inbox[0].Body != "thinking of you" {
		t.Fatalf("inbox=%v err=%v", inbox, err)
	}
	if err := s.MarkInboxNoteRead(owner.ID, note.ID); err != nil {
		t.Fatal(err)
	}

	if _, err := s.RevokeShare(owner.ID); err != nil {
		t.Fatal(err)
	}
	partnerState, err := s.GetShareState(partner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if partnerState.Status != model.ShareRevoked {
		t.Fatalf("expected partner revoked, got %+v", partnerState)
	}
	if _, err := s.CalendarSubjectID(partner.ID); err == nil {
		t.Fatal("expected inactive share after revoke")
	}
}

func TestDeleteUserRemovesData(t *testing.T) {
	s := NewMemoryStore()
	user, err := s.CreateUser("gone@example.com", "Gone", "password123")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpsertEntry(user.ID, "2026-10-01", model.UpsertRequest{Taken: model.BoolPtr(true), Notes: "x"}); err != nil {
		t.Fatal(err)
	}
	if err := s.CreateSession(user.ID, "tok", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteUser(user.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.GetUserByID(user.ID); err == nil {
		t.Fatal("expected user gone")
	}
	entries, _ := s.ListEntries(user.ID, 2026, 10)
	if len(entries) != 0 {
		t.Fatalf("expected entries cleared, got %d", len(entries))
	}
}

func TestDeletingPartnerRevokesTheShare(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		{
			owner, _ := s.LinkWorkOSIdentity("o-"+name, "o-"+name+"@example.com", "O", true)
			partner, _ := s.LinkWorkOSIdentity("p-"+name, "p-"+name+"@example.com", "P", true)
			if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
				t.Fatal(err)
			}
			share, _ := s.EnableShare(owner.ID)
			if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
				t.Fatal(err)
			}
			if err := s.DeleteUser(partner.ID); err != nil {
				t.Fatal(err)
			}
			state, err := s.GetShareState(owner.ID)
			if err != nil || state.Status != model.ShareNone {
				t.Fatalf("owner share after partner deleted: %+v %v", state, err)
			}
			if _, err := s.EnableShare(owner.ID); err != nil {
				t.Fatalf("owner must be able to invite again: %v", err)
			}
			if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
				t.Fatal(err)
			}
		}
	})
}

func TestPurgeExpiredKeepsLiveData(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		{
			u, _ := s.LinkWorkOSIdentity("u-"+name, "u-"+name+"@example.com", "U", true)
			if err := s.CreateSession(u.ID, "live", time.Now().Add(time.Hour)); err != nil {
				t.Fatal(err)
			}
			if err := s.CreateOAuthAttempt("old", "b", "v", "n", time.Now().Add(time.Second)); err != nil {
				t.Fatal(err)
			}
			if err := s.PurgeExpired(time.Now().Add(2 * time.Second)); err != nil {
				t.Fatal(err)
			}
			if _, err := s.ConsumeOAuthAttempt("old", "b"); err == nil {
				t.Fatal("expired attempt survived the purge")
			}
			if _, err := s.GetUserBySession("live"); err != nil {
				t.Fatalf("live session purged: %v", err)
			}
		}
	})
}

// forEachStore runs fn against the memory store and, when TEST_DATABASE_URL
// is set, PostgreSQL.
func forEachStore(t *testing.T, fn func(t *testing.T, name string, s Store)) {
	t.Run("memory", func(t *testing.T) { fn(t, "memory", NewMemoryStore()) })
	t.Run("postgres", func(t *testing.T) { fn(t, "postgres", pgTestStore(t)) })
}

func TestSentNotesListedForTheirAuthor(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		owner, _ := s.LinkWorkOSIdentity("so-"+name, "so-"+name+"@example.com", "O", true)
		partner, _ := s.LinkWorkOSIdentity("sp-"+name, "sp-"+name+"@example.com", "P", true)
		if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
			t.Fatal(err)
		}
		share, _ := s.EnableShare(owner.ID)
		if _, err := s.AcceptShare(partner.ID, share.InviteCode); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreatePartnerNote(partner.ID, "for you"); err != nil {
			t.Fatal(err)
		}
		sent, err := s.ListSentPartnerNotes(partner.ID)
		if err != nil || len(sent) != 1 || sent[0].Body != "for you" {
			t.Fatalf("sent notes: %+v %v", sent, err)
		}
		if mine, _ := s.ListSentPartnerNotes(owner.ID); len(mine) != 0 {
			t.Fatalf("owner wrote no notes, got %+v", mine)
		}
	})
}
