package cycle

import "testing"

func TestAgeAtCountsBirthMonth(t *testing.T) {
	cases := []struct {
		birth, today string
		want         int
	}{
		{"1981-11", "2026-11-01", 45},
		{"1981-12", "2026-11-30", 44},
		{"1981-01", "2026-01-01", 45},
	}
	for _, c := range cases {
		if got, ok := AgeAt(c.birth, day(c.today)); !ok || got != c.want {
			t.Errorf("AgeAt(%s, %s) = %d %v, want %d", c.birth, c.today, got, ok, c.want)
		}
	}
	if _, ok := AgeAt("1981-13", day("2026-11-01")); ok {
		t.Error("invalid month accepted")
	}
}

func TestSuggestStage(t *testing.T) {
	today := "2026-11-01"
	cases := []struct {
		name, current, birth string
		days                 []string
		want                 string
	}{
		{"no data", "cycling", "", nil, ""},
		{"young cycling", "cycling", "1995-03", span("2026-10-20", 4), ""},
		{"age 45 suggests perimenopause", "cycling", "1981-11", nil, "perimenopause"},
		{"age 44 is still cycling", "cycling", "1981-12", nil, ""},
		{"age 55 suggests perimenopause", "cycling", "1971-11", span("2026-10-01", 3), "perimenopause"},
		{"age 56 without history is cycling", "cycling", "1970-10", nil, ""},
		{"already perimenopause", "perimenopause", "1975-05", nil, ""},
		{"12 months without a period", "cycling", "1975-05", []string{"2025-11-01"}, "menopause"},
		{"no birth month, no menopause", "cycling", "", []string{"2025-11-01"}, ""},
		{"under 45 a long gap is not menopause", "cycling", "1995-03", []string{"2025-01-01"}, ""},
		{"just under 12 months", "perimenopause", "1975-05", []string{"2025-11-02"}, ""},
		{"menopause beats age", "perimenopause", "1975-05", []string{"2024-02-10", "2025-06-01"}, "menopause"},
		{"latest period counts, not the first", "perimenopause", "1975-05", []string{"2024-01-01", "2026-09-01"}, ""},
		{"future days ignored", "perimenopause", "1975-05", []string{"2025-10-01", "2026-12-01"}, "menopause"},
		{"never back from menopause", "menopause", "1990-01", span("2026-10-20", 4), ""},
		{"never back from perimenopause", "perimenopause", "1990-01", nil, ""},
		{"unknown current treated as cycling", "", "1980-01", nil, "perimenopause"},
	}
	for _, c := range cases {
		if got := SuggestStage(c.current, c.birth, c.days, day(today)); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}
