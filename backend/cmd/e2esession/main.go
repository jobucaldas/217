package main

import (
	"crypto/rand"
	"encoding/base64"
	"flag"
	"fmt"
	"log"
	"time"

	"217/backend/db"
	"217/backend/internal/store"
)

func main() {
	databaseURL := flag.String("db", "", "PostgreSQL connection string")
	email := flag.String("email", "screenshots@example.invalid", "seed user email")
	name := flag.String("name", "Screenshot User", "seed user name")
	duration := flag.Duration("duration", 15*time.Minute, "session lifetime")
	flag.Parse()
	if *databaseURL == "" {
		log.Fatal("-db is required")
	}
	if err := db.RunMigrations(*databaseURL); err != nil {
		log.Fatal(err)
	}
	s, err := store.NewPGStore(*databaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer s.Close()
	user, err := s.LinkGoogleIdentity("e2e:"+*email, *email, *name, false)
	if err != nil {
		log.Fatal(err)
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		log.Fatal(err)
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	if err := s.CreateSession(user.ID, token, time.Now().UTC().Add(*duration), "e2esession", ""); err != nil {
		log.Fatal(err)
	}
	fmt.Print(token)
}
