// Package cycle predicts upcoming periods and PMS windows from logged period days.
package cycle

import (
	"sort"
	"time"

	"217/backend/internal/model"
)

// SymptomForecast summarizes an owner's own symptom pattern on a future date.
type SymptomForecast struct {
	Symptom string `json:"symptom"`
	Date    string `json:"date"`
	Hits    int    `json:"hits"`
	Cycles  int    `json:"cycles_considered"`
}

// ForecastSymptoms maps each symptom log to the nearest period start (day 1),
// then compares same cycle-day windows across separate logged cycles.
func ForecastSymptoms(entries []*model.Entry, periodStarts []string, upcoming []string, cycleLength int) []SymptomForecast {
	starts := make([]time.Time, 0, len(periodStarts))
	for _, raw := range periodStarts {
		if d, err := time.Parse(layout, raw); err == nil {
			starts = append(starts, d)
		}
	}
	sort.Slice(starts, func(i, j int) bool { return starts[i].Before(starts[j]) })
	unique := starts[:0]
	for _, start := range starts {
		if len(unique) == 0 || !unique[len(unique)-1].Equal(start) {
			unique = append(unique, start)
		}
	}
	starts = unique
	if len(starts) < 2 || cycleLength <= 0 {
		return []SymptomForecast{}
	}
	logs := make([]map[int]map[string]bool, len(starts)-1)
	for i := range logs {
		logs[i] = map[int]map[string]bool{}
	}
	for _, e := range entries {
		d, err := time.Parse(layout, e.Date)
		if err != nil || len(e.Symptoms) == 0 {
			continue
		}
		idx := -1
		for i, start := range starts {
			if !start.After(d) {
				idx = i
			} else {
				break
			}
		}
		if idx < 0 || idx+1 >= len(starts) {
			continue
		}
		interval := int(starts[idx+1].Sub(starts[idx]).Hours() / 24)
		if interval < minCycle || interval > maxCycle {
			continue
		}
		cd := int(d.Sub(starts[idx]).Hours()/24) + 1
		if cd <= 0 || d.After(starts[idx+1]) {
			continue
		}
		if logs[idx][cd] == nil {
			logs[idx][cd] = map[string]bool{}
		}
		for _, symptom := range e.Symptoms {
			logs[idx][cd][symptom] = true
		}
	}
	// Per-cycle windows are evaluated against each upcoming cycle day.
	known := map[string]bool{}
	for _, byDay := range logs {
		for _, symptoms := range byDay {
			for s := range symptoms {
				known[s] = true
			}
		}
	}
	result := []SymptomForecast{}
	for _, raw := range upcoming {
		future, err := time.Parse(layout, raw)
		if err != nil {
			continue
		}
		anchor := starts[len(starts)-1]
		if future.Before(anchor) {
			continue
		}
		delta := int(future.Sub(anchor).Hours() / 24)
		cd := delta%cycleLength + 1
		for symptom := range known {
			hits, considered := 0, 0
			for i := 0; i < len(starts)-1; i++ {
				interval := int(starts[i+1].Sub(starts[i]).Hours() / 24)
				if interval < minCycle || interval > maxCycle {
					continue
				}
				considered++
				hit := false
				for _, delta := range []int{-1, 0, 1} {
					dayNo := cd + delta
					if dayNo < 1 || dayNo > interval {
						continue
					}
					ss := logs[i][dayNo]
					if ss[symptom] {
						hit = true
					}
				}
				if hit {
					hits++
				}
			}
			if considered >= 3 && hits >= 3 && hits*2 >= considered {
				result = append(result, SymptomForecast{Symptom: symptom, Date: raw, Hits: hits, Cycles: considered})
			}
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Date == result[j].Date {
			return result[i].Symptom < result[j].Symptom
		}
		return result[i].Date < result[j].Date
	})
	return result
}

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
