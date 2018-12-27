package main

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/fiatjaf/accountd"
	"github.com/gorilla/websocket"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/orcaman/concurrent-map"
	"github.com/rs/zerolog"
)

var err error
var pg *sqlx.DB
var log = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).With().Logger()
var acd = accountd.NewClient()
var serviceURL = os.Getenv("SERVICE_URL")
var mainHostname = os.Getenv("MAIN_HOSTNAME")
var connections = cmap.New()

func main() {
	pg, err = sqlx.Connect("postgres", os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal().
			Err(err).
			Msg("error connecting to postgres")
	}

	http.HandleFunc("/trello-list-id", trelloListIdHandle)
	http.HandleFunc("/trello", onboardTrello)
	http.HandleFunc("/trello/instant-site", func(w http.ResponseWriter, r *http.Request) {
		trelloInstantSite(pg, w, r)
	})

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Upgrade(w, r, w.Header(), 1024, 1024)
		if err != nil {
			http.Error(w, "Could not open websocket connection", http.StatusBadRequest)
			return
		}

		handle(pg, conn)
	})
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "index.html")
	})
	http.Handle("/static/", http.FileServer(http.Dir("./")))
	http.HandleFunc("/whoami", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, true)
		if !ok {
			return
		}
		json.NewEncoder(w).Encode(user)
	})
	http.HandleFunc("/list-sites", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		// fetch existing sites for this user
		sites, err := listSites(pg, user)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Msg("couldn't fetch sites for user")
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(sites)
	})
	http.HandleFunc("/create-site", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var data struct {
			Domain string `json:"domain"`
		}
		err := json.NewDecoder(r.Body).Decode(&data)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		id, err := createSite(pg, user, data.Domain)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Str("domain", data.Domain).
				Msg("couldn't create site")
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(id)
	})
	http.HandleFunc("/get-site", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var site Site
		err := json.NewDecoder(r.Body).Decode(&site)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err = fetchSite(pg, user, site.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't fetch site")
			http.Error(w, err.Error(), 500)
			return
		}

		json.NewEncoder(w).Encode(site)
	})
	http.HandleFunc("/update-site", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var site Site
		err := json.NewDecoder(r.Body).Decode(&site)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err = updateSiteData(pg, user, site.Id, site.Data)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't update site data")
			http.Error(w, err.Error(), 500)
			return
		}

		json.NewEncoder(w).Encode(site)
	})
	http.HandleFunc("/delete-site", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var site Site
		err := json.NewDecoder(r.Body).Decode(&site)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err = fetchSite(pg, user, site.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't fetch site")
			http.Error(w, err.Error(), 500)
			return
		}

		err = removeBucket(site.Domain)
		if err != nil {
			log.Error().
				Err(err).
				Str("domain", site.Domain).
				Msg("couldn't delete bucket on delete-site")
			http.Error(w, err.Error(), 500)
			return
		}

		if strings.HasSuffix(site.Domain, mainHostname) {
			err = removeSubdomainDNS(site.Domain)
			if err != nil {
				log.Error().
					Err(err).
					Str("domain", site.Domain).
					Msg("couldn't remove dns record")
				http.Error(w, err.Error(), 500)
				return
			}
		}

		err = deleteSite(pg, user, site.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't delete site from db")
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(200)
	})
	http.HandleFunc("/add-source", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var site Site
		err := json.NewDecoder(r.Body).Decode(&site)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err = addSource(pg, user, site.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't add source")
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(site)
	})
	http.HandleFunc("/update-source", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var source Source
		err := json.NewDecoder(r.Body).Decode(&source)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err := updateSource(pg, user, source)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("source", source.Id).
				Msg("couldn't update source")
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(site)
	})
	http.HandleFunc("/delete-source", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var source Source
		err := json.NewDecoder(r.Body).Decode(&source)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err := removeSource(pg, user, source.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("source", source.Id).
				Msg("couldn't remove source")
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(site)
	})
	http.HandleFunc("/publish", func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth(r, w, false)
		if !ok {
			return
		}

		var site Site
		err := json.NewDecoder(r.Body).Decode(&site)
		if err != nil {
			http.Error(w, err.Error(), 400)
		}

		site, err = fetchSite(pg, user, site.Id)
		if err != nil {
			log.Error().
				Err(err).
				Str("user", user).
				Int("site", site.Id).
				Msg("couldn't fetch site")
			http.Error(w, err.Error(), 500)
			return
		}

		var conn *websocket.Conn
		iconn, ok := connections.Get(user)
		if ok {
			conn, ok = iconn.(*websocket.Conn)
		}

		if conn == nil {
			log.Error().
				Err(err).
				Str("user", user).
				Msg("need a valid websocket connection when publishing.")
			http.Error(w, err.Error(), 403)
			return
		}

		w.WriteHeader(200)

		err = publish(site, conn)
		if err != nil {
			log.Error().
				Err(err).
				Int("site", site.Id).
				Msg("error publishing")
			http.Error(w, err.Error(), 500)
			return
		}
	})

	port := os.Getenv("PORT")
	log.Print("listening on port " + port)
	panic(http.ListenAndServe(":"+port, nil))
}

func auth(r *http.Request, w http.ResponseWriter, rewrite bool) (user string, ok bool) {
	token := strings.Split(r.Header.Get("Authorization"), " ")[1]
	tokendata, err := acd.VerifyAuth(token)
	if err != nil {
		http.Error(w, "wrong authorization token: "+token, 401)
		return "", false
	}

	if rewrite {
		n, err := rewriteAccounts(pg, tokendata)
		if err != nil {
			log.Warn().Err(err).Str("user", user).Msg("failed to rewrite accounts")
		}
		if n > 0 {
			log.Info().Int("n", n).Str("user", user).Msg("rewritten accounts")
		}
	}

	return tokendata.User.Name, true
}

func handle(pg *sqlx.DB, conn *websocket.Conn) {
	defer conn.Close()
	var user string
	var userch = make(chan string, 1)

	go notLoggedNotify(conn, userch)
	for {
		typ, bm, err := conn.ReadMessage()
		if err != nil || typ != websocket.TextMessage {
			break
		}
		sm := string(bm)
		m := strings.SplitN(sm, " ", 2)

		if user == "" && m[0] != "login" {
			log.Warn().Msg("not logged. waiting for login message.")
			return
		}

		switch m[0] {
		case "login":
			tokendata, err := acd.VerifyAuth(m[1])
			userch <- tokendata.User.Name

			if err != nil {
				log.Error().
					Err(err).
					Str("token", m[1]).
					Msg("failed to verify auth token")
				return
			}
			connections.Set(user, conn)
			break
		}

	}
}

func notLoggedNotify(conn *websocket.Conn, userch chan string) {
	timeout := make(chan string, 1)
	go func() {
		time.Sleep(1 * time.Second)
		timeout <- ""
	}()

	select {
	case user := <-userch:
		if user != "" {
			return
		}
	case <-timeout:
		err := conn.WriteMessage(websocket.TextMessage, []byte("not-logged"))
		if err != nil {
			log.Warn().
				Err(err).
				Msg("failed to send not-logged message")
		}
	}
}
