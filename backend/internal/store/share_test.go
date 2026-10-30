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

	if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
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

func TestListAccountSharesIncludesAllStatuses(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		owner, err := s.LinkWorkOSIdentity("share-list-owner-"+name, "share-list-owner-"+name+"@example.com", "Owner", true)
		if err != nil {
			t.Fatal(err)
		}
		partner, err := s.LinkWorkOSIdentity("share-list-partner-"+name, "share-list-partner-"+name+"@example.com", "Partner", true)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
			t.Fatal(err)
		}
		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}

		open, err := s.EnableShare(owner.ID)
		if err != nil {
			t.Fatal(err)
		}
		shares, err := s.ListAccountShares(owner.ID)
		if err != nil || len(shares) != 1 || shares[0].Status != model.ShareOpen || shares[0].PartnerID != "" {
			t.Fatalf("open share: %+v, %v", shares, err)
		}

		if _, err := s.AcceptShare(partner.ID, open.InviteCode); err != nil {
			t.Fatal(err)
		}
		shares, err = s.ListAccountShares(owner.ID)
		if err != nil || len(shares) != 1 || shares[0].Status != model.ShareActive || shares[0].PartnerID != partner.ID {
			t.Fatalf("active share: %+v, %v", shares, err)
		}

		if _, err := s.RevokeShare(owner.ID); err != nil {
			t.Fatal(err)
		}
		if _, err := s.EnableShare(owner.ID); err != nil {
			t.Fatal(err)
		}
		shares, err = s.ListAccountShares(owner.ID)
		if err != nil || len(shares) != 2 {
			t.Fatalf("revoked + open shares: %+v, %v", shares, err)
		}
		statuses := map[string]bool{}
		for _, share := range shares {
			statuses[share.Status] = true
		}
		if !statuses[model.ShareRevoked] || !statuses[model.ShareOpen] {
			t.Fatalf("expected revoked and open shares, got %+v", shares)
		}
	})
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
			if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
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
			if err := s.CreateOAuthAttempt("old", "b", "v", "n", "", time.Now().Add(time.Second)); err != nil {
				t.Fatal(err)
			}
			oldSub, err := s.SavePushSubscription(u.ID, model.PushSubscriptionRequest{Endpoint: "https://old.example/sub"})
			if err != nil {
				t.Fatal(err)
			}
			recentSub, err := s.SavePushSubscription(u.ID, model.PushSubscriptionRequest{Endpoint: "https://recent.example/sub"})
			if err != nil {
				t.Fatal(err)
			}
			base := time.Now().UTC()
			_, _ = s.ClaimReminderDelivery(oldSub.ID, base.AddDate(0, 0, -31), base)
			_, _ = s.ClaimReminderDelivery(recentSub.ID, base.AddDate(0, 0, -2), base)
			if err := s.PurgeExpired(time.Now().Add(2 * time.Second)); err != nil {
				t.Fatal(err)
			}
			if _, err := s.ConsumeOAuthAttempt("old", "b"); err == nil {
				t.Fatal("expired attempt survived the purge")
			}
			if name == "memory" {
				ms := s.(*MemoryStore)
				ms.mu.RLock()
				_, oldExists := ms.deliveries[deliveryKey(oldSub.ID, base.AddDate(0, 0, -31))]
				_, recentExists := ms.deliveries[deliveryKey(recentSub.ID, base.AddDate(0, 0, -2))]
				ms.mu.RUnlock()
				if oldExists || !recentExists {
					t.Fatalf("delivery retention old=%v recent=%v", oldExists, recentExists)
				}
			} else {
				ps := s.(*PGStore)
				var oldCount, recentCount int
				_ = ps.db.QueryRow(`SELECT COUNT(*) FROM reminder_deliveries WHERE subscription_id=$1`, oldSub.ID).Scan(&oldCount)
				_ = ps.db.QueryRow(`SELECT COUNT(*) FROM reminder_deliveries WHERE subscription_id=$1`, recentSub.ID).Scan(&recentCount)
				if oldCount != 0 || recentCount != 1 {
					t.Fatalf("delivery retention old=%d recent=%d", oldCount, recentCount)
				}
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

// A zero-value RepeatMinutes means "unset", not "every 0 minutes": the store
// must seed the model default instead of persisting 0 (which PostgreSQL's
// repeat_minutes_check constraint rejects).
func TestUpsertReminderPreferenceDefaultsRepeatMinutes(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		u, err := s.LinkWorkOSIdentity("zero-"+name, "zero-"+name+"@example.com", "Zero", true)
		if err != nil {
			t.Fatal(err)
		}
		saved, err := s.UpsertReminderPreference(u.ID, model.ReminderPreference{Enabled: true, Time: "08:00", Timezone: "UTC"})
		if err != nil {
			t.Fatal(err)
		}
		if saved.RepeatMinutes != model.DefaultRepeatMinutes || saved.RepeatEnabled {
			t.Fatalf("zero-value repeat fields on upsert: %+v", saved)
		}
		reloaded, err := s.GetReminderPreference(u.ID)
		if err != nil {
			t.Fatal(err)
		}
		if reloaded.RepeatMinutes != model.DefaultRepeatMinutes || reloaded.RepeatEnabled {
			t.Fatalf("zero-value repeat fields on reload: %+v", reloaded)
		}
	})
}

func TestReminderTargetsRequireCurrentConsent(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		no, _ := s.LinkWorkOSIdentity("no-"+name, "no-"+name+"@example.com", "No", true)
		yes, _ := s.LinkWorkOSIdentity("yes-"+name, "yes-"+name+"@example.com", "Yes", true)
		for _, u := range []*model.User{no, yes} {
			_, err := s.SetRole(u.ID, model.RoleOwner)
			if err != nil {
				t.Fatal(err)
			}
			_, err = s.SavePushSubscription(u.ID, model.PushSubscriptionRequest{Endpoint: "https://" + u.ID + ".example/sub"})
			if err != nil {
				t.Fatal(err)
			}
			_, err = s.UpsertReminderPreference(u.ID, model.ReminderPreference{Enabled: true, Time: "08:00", Timezone: "UTC"})
			if err != nil {
				t.Fatal(err)
			}
		}
		if _, err := s.RecordConsent(yes.ID, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
		targets, err := s.ListReminderTargets()
		if err != nil {
			t.Fatal(err)
		}
		if len(targets) != 1 || targets[0].UserID != yes.ID {
			t.Fatalf("targets=%+v want consented subscriber only", targets)
		}
	})
}

func TestSentNotesListedForTheirAuthor(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		owner, _ := s.LinkWorkOSIdentity("so-"+name, "so-"+name+"@example.com", "O", true)
		partner, _ := s.LinkWorkOSIdentity("sp-"+name, "sp-"+name+"@example.com", "P", true)
		if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
			t.Fatal(err)
		}
		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
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

func TestSharingRequiresOwnerConsent(t *testing.T) {
	forEachStore(t, func(t *testing.T, name string, s Store) {
		owner, _ := s.LinkWorkOSIdentity("owner-"+name, "owner-"+name+"@example.com", "Owner", true)
		partner, _ := s.LinkWorkOSIdentity("partner-"+name, "partner-"+name+"@example.com", "Partner", true)
		if _, err := s.SetRole(owner.ID, model.RoleOwner); err != nil {
			t.Fatal(err)
		}
		// An invite created before the current notice existed.
		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
		invite, err := s.EnableShare(owner.ID)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion-1); err != nil {
			t.Fatal(err)
		}
		if _, err := s.AcceptShare(partner.ID, invite.InviteCode); err == nil || err.Error() != "calendar owner consent required" {
			t.Fatalf("accept without owner consent: err=%v", err)
		}

		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion); err != nil {
			t.Fatal(err)
		}
		if _, err := s.AcceptShare(partner.ID, invite.InviteCode); err != nil {
			t.Fatal(err)
		}
		if _, err := s.RecordConsent(owner.ID, model.ConsentVersion-1); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreatePartnerNote(partner.ID, "hi"); err == nil || err.Error() != "calendar owner consent required" {
			t.Fatalf("note without owner consent: err=%v", err)
		}
	})
}
