package passwordauth

import "strings"

// commonPasswords is a small embedded blocklist of the most-chosen passwords
// (top of the public breach corpora). It is a tripwire, not an exhaustive
// dictionary: anything on it is refused at sign-up and password change.
var commonPasswords = map[string]bool{
	"123456": true, "123456789": true, "12345678": true, "12345": true,
	"1234567": true, "1234567890": true, "qwerty": true, "qwerty123": true,
	"password": true, "password1": true, "password123": true, "passw0rd": true,
	"password123456": true, "password12345678": true, "password123456789": true,
	"abc123": true, "111111": true, "123123": true, "123321": true,
	"000000": true, "654321": true, "666666": true, "121212": true,
	"iloveyou": true, "admin": true, "administrator": true, "welcome": true,
	"welcome1": true, "login": true, "guest": true, "root": true,
	"monkey": true, "dragon": true, "letmein": true, "master": true,
	"sunshine": true, "princess": true, "flower": true, "hello": true,
	"freedom": true, "whatever": true, "qazwsx": true, "trustno1": true,
	"batman": true, "superman": true, "football": true, "baseball": true,
	"shadow": true, "michael": true, "jordan": true, "hunter": true,
	"charlie": true, "jennifer": true, "samsung": true, "google": true,
	"zaq12wsx": true, "1q2w3e4r": true, "1qaz2wsx": true, "asdfgh": true,
	"qwertyuiop": true, "starwars": true, "pokemon": true, "snoopy": true,
}

// WeakPassword reports whether password is too weak to accept: it only
// normalises case (no composition rules are enforced).
func WeakPassword(password string) bool {
	return commonPasswords[strings.ToLower(password)]
}
