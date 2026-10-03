package cycle

import (
	"testing"
	"time"
)

func day(s string) time.Time {
	t, err := time.Parse(layout, s)
	if err != nil {
		panic(err)
	}
	return t
}

func span(start string, n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = day(start).AddDate(0, 0, i).Format(layout)
	}
	return out
}

func TestPredictNoDataHasNoPredictions(t *testing.T) {
	info := Predict(nil, day("2026-10-03"))
	if len(info.Predictions) != 0 || !info.Estimated || info.CycleLength != DefaultCycleLength {
		t.Fatalf("unexpected: %+v", info)
	}
}

func TestPredictAveragesCyclesAndPeriodLength(t *testing.T) {
	var days []string
	days = append(days, span("2026-07-01", 4)...)
	days = append(days, span("2026-07-31", 4)...) // 30-day cycle
	days = append(days, span("2026-08-30", 4)...) // 30-day cycle
	days = append(days, span("2026-09-29", 2)...) // ongoing
	info := Predict(days, day("2026-10-01"))
	if info.Estimated || info.CycleLength != 30 || info.PeriodLength != 4 {
		t.Fatalf("unexpected stats: %+v", info)
	}
	if len(info.PeriodStarts) != 4 || info.PeriodStarts[3] != "2026-09-29" {
		t.Fatalf("starts: %v", info.PeriodStarts)
	}
	first := info.Predictions[0]
	if first.PeriodStart != "2026-10-29" || first.PeriodEnd != "2026-11-01" ||
		first.PMSStart != "2026-10-24" || first.PMSEnd != "2026-10-28" {
		t.Fatalf("first prediction: %+v", first)
	}
	if len(info.Predictions) != Predictions || info.Predictions[1].PeriodStart != "2026-11-28" {
		t.Fatalf("predictions: %+v", info.Predictions)
	}
}

func TestPredictSingleLoggedPeriodUsesDefaultCycle(t *testing.T) {
	info := Predict(span("2026-09-20", 5), day("2026-10-03"))
	if !info.Estimated || info.CycleLength != 28 || info.PeriodLength != 5 {
		t.Fatalf("unexpected: %+v", info)
	}
	if info.Predictions[0].PeriodStart != "2026-10-18" || info.Predictions[0].PMSStart != "2026-10-13" {
		t.Fatalf("prediction: %+v", info.Predictions[0])
	}
}

func TestPredictSkipsCyclesAlreadyPast(t *testing.T) {
	// Last logged start 2026-07-01; 28-day cycles → 07-29, 08-26, 09-23 (ends 09-27), 10-21.
	info := Predict(span("2026-07-01", 5), day("2026-10-03"))
	if info.Predictions[0].PeriodStart != "2026-10-21" {
		t.Fatalf("prediction: %+v", info.Predictions[0])
	}
	// Today inside a predicted period keeps that period as the first prediction.
	info = Predict(span("2026-07-01", 5), day("2026-09-25"))
	if info.Predictions[0].PeriodStart != "2026-09-23" {
		t.Fatalf("ongoing prediction: %+v", info.Predictions[0])
	}
}

func TestPredictMergesSmallGapsAndIgnoresOutliers(t *testing.T) {
	days := []string{"2026-08-01", "2026-08-02", "2026-08-04", "2026-08-05"} // one period with a gap
	days = append(days, span("2026-08-29", 4)...)                            // 28-day cycle
	days = append(days, "2026-08-29", "bad-date", "2026-12-01")              // duplicate, junk, future
	info := Predict(days, day("2026-09-10"))
	if len(info.PeriodStarts) != 2 || info.CycleLength != 28 || info.PeriodLength != 5 {
		t.Fatalf("unexpected: %+v", info)
	}
}

func TestPredictStopsOnStaleHistory(t *testing.T) {
	info := Predict(span("2025-01-01", 5), day("2026-10-03"))
	if len(info.Predictions) != 0 || len(info.PeriodStarts) != 1 {
		t.Fatalf("expected no predictions for stale history: %+v", info)
	}
}
