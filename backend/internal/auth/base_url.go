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
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return "", fmt.Errorf("APP_BASE_URL must be an absolute http(s) origin")
	}
	if u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") || u.RawPath != "" {
		return "", fmt.Errorf("APP_BASE_URL must be origin-only without credentials, path, query, or fragment")
	}
	if u.Scheme == "http" {
		host := u.Hostname()
		ip := net.ParseIP(host)
		if !strings.EqualFold(host, "localhost") && (ip == nil || !ip.IsLoopback()) {
			return "", fmt.Errorf("APP_BASE_URL requires HTTPS except for localhost or loopback IPs")
		}
	}
	return u.Scheme + "://" + u.Host, nil
}
