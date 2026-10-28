package model

import "testing"

func TestValidRepeatMinutes(t *testing.T) {
	cases := map[int]bool{
		-1: false, 0: false, 1: true, 15: true, 120: true, 121: false, 1000: false,
	}
	for minutes, want := range cases {
		if got := ValidRepeatMinutes(minutes); got != want {
			t.Errorf("ValidRepeatMinutes(%d) = %v, want %v", minutes, got, want)
		}
	}
}

func TestReminderPreferenceRepeatDefaultsToDisabled(t *testing.T) {
	var pref ReminderPreference
	if pref.RepeatEnabled {
		t.Fatalf("repeat must default to off: %+v", pref)
	}
}
