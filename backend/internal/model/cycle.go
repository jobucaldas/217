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
	// DefaultPillRepeatMinutes seeds the field the first time a partner
	// turns the repeat on.
	DefaultPillRepeatMinutes = 15
	MinPillRepeatMinutes     = 1
	MaxPillRepeatMinutes     = 120
)

// PartnerAlertPreference holds a partner's notification toggles and times.
type PartnerAlertPreference struct {
	PMSEnabled  bool   `json:"pms_enabled"`
	PMSTime     string `json:"pms_time"`
	PillEnabled bool   `json:"pill_enabled"`
	PillTime    string `json:"pill_time"`
	// PillRepeatEnabled repeats the pill-not-logged alert every
	// PillRepeatMinutes until the pill is logged or the day ends.
	PillRepeatEnabled bool `json:"pill_repeat_enabled"`
	PillRepeatMinutes int  `json:"pill_repeat_minutes"`
}

func DefaultPartnerAlertPreference() PartnerAlertPreference {
	return PartnerAlertPreference{
		PMSTime:           DefaultPMSTime,
		PillTime:          DefaultPillTime,
		PillRepeatMinutes: DefaultPillRepeatMinutes,
	}
}

// ValidPillRepeatMinutes reports whether minutes is in the allowed interval,
// regardless of whether the repeat is currently enabled.
func ValidPillRepeatMinutes(minutes int) bool {
	return minutes >= MinPillRepeatMinutes && minutes <= MaxPillRepeatMinutes
}
