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
)

// PartnerAlertPreference holds a partner's notification toggles and times.
type PartnerAlertPreference struct {
	PMSEnabled  bool   `json:"pms_enabled"`
	PMSTime     string `json:"pms_time"`
	PillEnabled bool   `json:"pill_enabled"`
	PillTime    string `json:"pill_time"`
}

func DefaultPartnerAlertPreference() PartnerAlertPreference {
	return PartnerAlertPreference{PMSTime: DefaultPMSTime, PillTime: DefaultPillTime}
}
