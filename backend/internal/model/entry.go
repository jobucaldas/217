package model

import "time"

type Entry struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Date      string    `json:"date"`
	Taken     bool      `json:"taken"`
	Notes     string    `json:"notes"`
	Heart     bool      `json:"heart"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type UpsertRequest struct {
	Taken bool   `json:"taken"`
	Notes string `json:"notes"`
	Heart bool   `json:"heart"`
}

type MonthEntries struct {
	Year    int      `json:"year"`
	Month   int      `json:"month"`
	Entries []*Entry `json:"entries"`
}

type Stats struct {
	Year       int `json:"year"`
	Month      int `json:"month"`
	TotalDays  int `json:"total_days"`
	TakenDays  int `json:"taken_days"`
	MissedDays int `json:"missed_days"`
	Streak     int `json:"streak"`
}
