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

	if _, err := s.UpsertEntry(owner.ID, "2026-10-01", model.UpsertRequest{Taken: true}); err != nil {
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
	if _, err := s.UpsertEntry(user.ID, "2026-10-01", model.UpsertRequest{Taken: true, Notes: "x"}); err != nil {
		t.Fatal(err)
	}
	if err := s.CreateSession(user.ID, "tok", time.Now().Add(time.Hour), "ua", "ip"); err != nil {
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
