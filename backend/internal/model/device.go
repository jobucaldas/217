package model

import "time"

// DeviceKeyIdleRetention is how long an unused device key stays valid: a
// phone left in a drawer longer than this signs in again.
const DeviceKeyIdleRetention = 180 * 24 * time.Hour

// MaxDeviceKeysPerUser caps registered devices; the oldest goes first.
const MaxDeviceKeysPerUser = 10

// DeviceKey is a signed-in device that can renew its own session (export).
type DeviceKey struct {
	ID         string    `json:"id"`
	CreatedAt  time.Time `json:"created_at"`
	LastUsedAt time.Time `json:"last_used_at"`
}
