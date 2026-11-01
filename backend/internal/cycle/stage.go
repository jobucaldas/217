package cycle

import (
	"time"

	"217/backend/internal/model"
)

const (
	// PerimenopauseMinAge and PerimenopauseMaxAge bound the ages (inclusive)
	// at which perimenopause usually happens.
	PerimenopauseMinAge = 45
	PerimenopauseMaxAge = 55
	// MenopauseMonths without a period mark menopause.
	MenopauseMonths = 12
)

// BirthMonthLayout is the stored birth date precision: month and year.
const BirthMonthLayout = "2006-01"

var stageRank = map[string]int{
	model.StageCycling:       0,
	model.StagePerimenopause: 1,
	model.StageMenopause:     2,
}

// AgeAt is the age in whole years on today for someone born in birthMonth
// (YYYY-MM), counting the birthday as the first of that month. ok is false
// when birthMonth does not parse.
func AgeAt(birthMonth string, today time.Time) (age int, ok bool) {
	born, err := time.Parse(BirthMonthLayout, birthMonth)
	if err != nil {
		return 0, false
	}
	age = today.Year() - born.Year()
	if today.Month() < born.Month() {
		age--
	}
	return age, true
}

// LatestPeriodDay returns the most recent YYYY-MM-DD day not after today,
// or "" when there is none.
func LatestPeriodDay(days []string, today time.Time) string {
	today = dateOnly(today)
	latest := ""
	var latestT time.Time
	for _, d := range days {
		t, err := time.Parse(layout, d)
		if err != nil || t.After(today) {
			continue
		}
		if latest == "" || t.After(latestT) {
			latest, latestT = d, t
		}
	}
	return latest
}

// SuggestStage returns the reproductive stage the owner's data points to,
// or "" when there is nothing to suggest:
//   - menopause: at least one logged period day, the latest at least
//     MenopauseMonths before today;
//   - perimenopause: aged PerimenopauseMinAge to PerimenopauseMaxAge;
//   - otherwise cycling.
//
// Only moves forward (cycling → perimenopause → menopause) are suggested, so
// a stage picked by hand is never nagged back. birthMonth is YYYY-MM or "";
// periodDays are YYYY-MM-DD; today is the caller's local date.
func SuggestStage(current, birthMonth string, periodDays []string, today time.Time) string {
	today = dateOnly(today)
	age, hasAge := AgeAt(birthMonth, today)
	latest := LatestPeriodDay(periodDays, today)
	if !hasAge && latest == "" {
		return ""
	}
	suggested := model.StageCycling
	if latest != "" {
		last, _ := time.Parse(layout, latest)
		if !last.AddDate(0, MenopauseMonths, 0).After(today) {
			suggested = model.StageMenopause
		}
	}
	if suggested == model.StageCycling && hasAge && age >= PerimenopauseMinAge && age <= PerimenopauseMaxAge {
		suggested = model.StagePerimenopause
	}
	cur, known := stageRank[current]
	if !known {
		cur = stageRank[model.StageCycling]
	}
	if stageRank[suggested] <= cur {
		return ""
	}
	return suggested
}
