package handler

import (
	"net/http/httptest"
	"strings"
	"testing"
)

// TestClientIPKeyIPv6 pins the per-IP key form: two addresses in one /64
// share a key, different /64s get different keys, IPv4 is per-address.
func TestClientIPKeyIPv6(t *testing.T) {
	key := func(ip string) string {
		r := httptest.NewRequest("POST", "/", nil)
		if strings.Contains(ip, ":") {
			r.RemoteAddr = "[" + ip + "]:1234"
		} else {
			r.RemoteAddr = ip + ":1234"
		}
		return clientIPKey("pw:", clientIP(r))
	}
	// Two addresses in the same /64 must collide onto one key.
	a := key("2001:db8:1:2:aaaa:bbbb:cccc:1")
	b := key("2001:db8:1:2:dddd:eeee:ffff:2")
	if a != b {
		t.Fatalf("same /64 must share a key: %q vs %q", a, b)
	}
	// A different /64 must get a different key.
	c := key("2001:db8:1:3::1")
	if a == c {
		t.Fatalf("different /64s must differ, both %q", a)
	}
	// IPv4 stays per-address.
	v1 := key("203.0.113.1")
	v2 := key("203.0.113.2")
	if v1 == v2 {
		t.Fatalf("IPv4 addresses must differ, both %q", v1)
	}
	if v1 != "pw:203.0.113.1" {
		t.Fatalf("IPv4 key shape changed: %q", v1)
	}
}
