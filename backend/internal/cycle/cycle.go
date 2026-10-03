// Package cycle predicts upcoming periods and PMS windows from logged period days.
package cycle

import (
	"sort"
	"time"

	"217/backend/internal/model"
)

const (
	DefaultCycleLength  = 28
	DefaultPeriodLength = 5
	// PMSDays is how many days before a predicted period count as the PMS window.
	PMSDays = 5
	// Predictions is how many upcoming cycles are returned.
	Predictions = 3
	// HistoryDays bounds how far back logged period days are read.
	HistoryDays = 400

	minCycle   = 15
	maxCycle   = 60
	maxSamples = 6
	// Stop predicting when the latest logged period is this old: stale data
	// would only produce noise.
	staleAfterDays = 180
	// Logged days at most this far apart belong to the same period.
	maxGapDays = 2
)

const layout = "2006-01-02"

// Predict groups logged period days into periods and projects the next ones.
// today is the caller's local date; days are YYYY-MM-DD strings.
func Predict(days []string, today time.Time) model.CycleInfo {
	today = dateOnly(today)
	info := model.CycleInfo{
		PeriodStarts: []string{},
		CycleLength:  DefaultCycleLength,
		PeriodLength: DefaultPeriodLength,
		Estimated:    true,
		Predictions:  []model.CycleWindow{},
	}

	parsed := make([]time.Time, 0, len(days))
	seen := map[string]bool{}
	for _, d := range days {
		t, err := time.Parse(layout, d)
		if err != nil || seen[d] || t.After(today) {
			continue
		}
		seen[d] = true
		parsed = append(parsed, t)
	}
	if len(parsed) == 0 {
		return info
	}
	sort.Slice(parsed, func(i, j int) bool { return parsed[i].Before(parsed[j]) })

	type run struct{ start, end time.Time }
	runs := []run{{parsed[0], parsed[0]}}
	for _, t := range parsed[1:] {
		last := &runs[len(runs)-1]
		if daysBetween(last.end, t) <= maxGapDays {
			last.end = t
			continue
		}
		runs = append(runs, run{t, t})
	}

	for _, r := range runs {
		info.PeriodStarts = append(info.PeriodStarts, r.start.Format(layout))
	}

	var cycles []int
	for i := 1; i < len(runs); i++ {
		if c := daysBetween(runs[i-1].start, runs[i].start); c >= minCycle && c <= maxCycle {
			cycles = append(cycles, c)
		}
	}
	if len(cycles) > 0 {
		info.CycleLength = roundedMean(tail(cycles, maxSamples))
		info.Estimated = false
	}

	// The latest run may still be ongoing, so it is not used for length.
	var lengths []int
	for _, r := range runs[:len(runs)-1] {
		lengths = append(lengths, daysBetween(r.start, r.end)+1)
	}
	if len(lengths) == 0 {
		lengths = []int{daysBetween(runs[0].start, runs[0].end) + 1}
	}
	info.PeriodLength = clamp(roundedMean(tail(lengths, maxSamples)), 2, 8)
	if len(runs) == 1 && info.PeriodLength < 3 {
		// A single short run is likely still being logged.
		info.PeriodLength = DefaultPeriodLength
	}

	last := runs[len(runs)-1].start
	if daysBetween(last, today) > staleAfterDays {
		return info
	}
	next := last.AddDate(0, 0, info.CycleLength)
	// Skip cycles whose predicted period already ended.
	for !next.AddDate(0, 0, info.PeriodLength-1).After(today.AddDate(0, 0, -1)) {
		next = next.AddDate(0, 0, info.CycleLength)
	}
	for i := 0; i < Predictions; i++ {
		info.Predictions = append(info.Predictions, model.CycleWindow{
			PeriodStart: next.Format(layout),
			PeriodEnd:   next.AddDate(0, 0, info.PeriodLength-1).Format(layout),
			PMSStart:    next.AddDate(0, 0, -PMSDays).Format(layout),
			PMSEnd:      next.AddDate(0, 0, -1).Format(layout),
		})
		next = next.AddDate(0, 0, info.CycleLength)
	}
	return info
}

func dateOnly(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func daysBetween(a, b time.Time) int {
	return int(dateOnly(b).Sub(dateOnly(a)).Hours() / 24)
}

func tail(values []int, n int) []int {
	if len(values) > n {
		return values[len(values)-n:]
	}
	return values
}

func roundedMean(values []int) int {
	sum := 0
	for _, v := range values {
		sum += v
	}
	return (sum*2 + len(values)) / (len(values) * 2)
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
