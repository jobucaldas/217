package model

import "testing"

func TestValidPillRepeatMinutes(t *testing.T) {
	cases := map[int]bool{
		-1: false, 0: false, 1: true, 15: true, 120: true, 121: false, 1000: false,
	}
	for minutes, want := range cases {
		if got := ValidPillRepeatMinutes(minutes); got != want {
			t.Errorf("ValidPillRepeatMinutes(%d) = %v, want %v", minutes, got, want)
		}
	}
}

func TestDefaultPartnerAlertPreferenceDisablesRepeat(t *testing.T) {
	pref := DefaultPartnerAlertPreference()
	if pref.PillRepeatEnabled {
		t.Fatalf("repeat must default to off: %+v", pref)
	}
	if pref.PillRepeatMinutes != DefaultPillRepeatMinutes {
		t.Fatalf("default minutes = %d, want %d", pref.PillRepeatMinutes, DefaultPillRepeatMinutes)
	}
}
