package model

// CycleWindow is one predicted period and the PMS days leading into it.
type CycleWindow struct {
	PeriodStart string `json:"period_start"`
	PeriodEnd   string `json:"period_end"`
	PMSStart    string `json:"pms_start"`
	PMSEnd      string `json:"pms_end"`
}

// CycleInfo summarizes logged period days and the next predicted cycles.
type CycleInfo struct {
	PeriodStarts []string `json:"period_starts"`
	CycleLength  int      `json:"cycle_length"`
	PeriodLength int      `json:"period_length"`
	// Estimated is true while fewer than two periods are logged (default cycle length).
	Estimated   bool          `json:"estimated"`
	Predictions []CycleWindow `json:"predictions"`
}

const (
	DefaultPMSTime  = "09:00"
	DefaultPillTime = "21:00"
	// PillRepeatOff is the stored value when pill alerts do not repeat.
	PillRepeatOff = 0
	// PillRepeatMaxMinutes is the longest allowed gap between repeated pill alerts.
	PillRepeatMaxMinutes = 120
)

// PartnerAlertPreference holds a partner's notification toggles and times.
// PillRepeatMinutes is PillRepeatOff (0) or an interval from 1 to
// PillRepeatMaxMinutes; a missing field decodes as off.
type PartnerAlertPreference struct {
	PMSEnabled        bool   `json:"pms_enabled"`
	PMSTime           string `json:"pms_time"`
	PillEnabled       bool   `json:"pill_enabled"`
	PillTime          string `json:"pill_time"`
	PillRepeatMinutes int    `json:"pill_repeat_minutes"`
}

func DefaultPartnerAlertPreference() PartnerAlertPreference {
	return PartnerAlertPreference{PMSTime: DefaultPMSTime, PillTime: DefaultPillTime, PillRepeatMinutes: PillRepeatOff}
}

// ValidPillRepeat reports whether minutes is off or within the allowed interval.
func ValidPillRepeat(minutes int) bool {
	return minutes == PillRepeatOff || (minutes >= 1 && minutes <= PillRepeatMaxMinutes)
}
