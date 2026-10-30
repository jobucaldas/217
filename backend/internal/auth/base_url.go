package auth

import (
	"fmt"
	"net"
	"net/url"
	"strings"
)

// ValidateAppBaseURL validates and canonicalizes the application's public origin.
// An empty value is allowed so OAuth can remain disabled in local deployments.
func ValidateAppBaseURL(raw string) (string, error) {
	if raw == "" {
		return "", nil
	}
	return validateOrigin("APP_BASE_URL", raw)
}

func validateOrigin(name, raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return "", fmt.Errorf("%s must be an absolute http(s) origin", name)
	}
	if u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") || u.RawPath != "" {
		return "", fmt.Errorf("%s must be origin-only without credentials, path, query, or fragment", name)
	}
	if u.Scheme == "http" {
		host := u.Hostname()
		ip := net.ParseIP(host)
		if !strings.EqualFold(host, "localhost") && (ip == nil || !ip.IsLoopback()) {
			return "", fmt.Errorf("%s requires HTTPS except for localhost or loopback IPs", name)
		}
	}
	return u.Scheme + "://" + u.Host, nil
}

// ParseAllowedOrigins returns the canonical origin followed by the extra
// origins in the comma-separated list, each validated like APP_BASE_URL and
// de-duplicated. A canonical origin is required when extras are given.
func ParseAllowedOrigins(canonical, extra string) ([]string, error) {
	var origins []string
	seen := map[string]bool{}
	add := func(o string) {
		if !seen[o] {
			seen[o] = true
			origins = append(origins, o)
		}
	}
	if canonical != "" {
		add(canonical)
	}
	for _, raw := range strings.Split(extra, ",") {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		o, err := validateOrigin("APP_ALLOWED_ORIGINS entry", raw)
		if err != nil {
			return nil, err
		}
		add(o)
	}
	if canonical == "" && len(origins) > 0 {
		return nil, fmt.Errorf("APP_ALLOWED_ORIGINS requires APP_BASE_URL")
	}
	return origins, nil
}

// MatchOriginHost returns the allowed origin whose host (including any port)
// equals host, case-insensitively, or "" when none does. Only allowlisted
// origins are ever returned, never the caller's input.
func MatchOriginHost(allowed []string, host string) string {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return ""
	}
	for _, o := range allowed {
		if u, err := url.Parse(o); err == nil && strings.ToLower(u.Host) == host {
			return o
		}
	}
	return ""
}

// BrowserCallbackPath is the AuthKit browser callback route on every origin.
const BrowserCallbackPath = "/api/auth/workos/callback"
