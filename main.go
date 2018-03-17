package main

import (
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/fiatjaf/accountd"
	"github.com/gorilla/websocket"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/rs/zerolog"
)

var log = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).With().Logger()
var acd = accountd.NewClient()

func main() {
	pg, err := sqlx.Connect("postgres", os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal().
			Err(err).
			Msg("error connecting to postgres")
	}

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Origin") != "http://"+r.Host {
			http.Error(w, "Origin not allowed", 403)
			return
		}

		conn, err := websocket.Upgrade(w, r, w.Header(), 1024, 1024)
		if err != nil {
			http.Error(w, "Could not open websocket connection", http.StatusBadRequest)
			return
		}

		handle(pg, conn)
	})

	http.Handle("/", http.FileServer(http.Dir("./")))

	port := os.Getenv("PORT")
	log.Print("listening on port " + port)
	panic(http.ListenAndServe(":"+port, nil))
}

func handle(pg *sqlx.DB, conn *websocket.Conn) {
	defer conn.Close()
	var user string
	var userch = make(chan string, 1)
	var sendMsg func(string)

	go notLoggedNotify(conn, userch)

	for {
		typ, bm, err := conn.ReadMessage()
		if err != nil || typ != websocket.TextMessage {
			log.Error().
				Err(err).
				Int("type", typ).
				Msg("error reading message")
			break
		}
		sm := string(bm)
		m := strings.SplitN(sm, " ", 2)

		log.Debug().
			Str("m", sm).
			Str("user", user).
			Msg("got message")

		if user == "" && m[0] != "login" {
			log.Warn().Msg("not logged. waiting for login message.")
			continue
		}

		switch m[0] {
		case "login":
			user, err = acd.VerifyAuth(m[1])
			userch <- user

			if err != nil {
				log.Error().
					Err(err).
					Str("token", m[1]).
					Msg("failed to verify auth token")
				sendMsg("notice error=" + err.Error())
				continue
			}
			log.Debug().Str("user", user).Msg("successful login")
			sendMsg = func(sm string) {
				log.Debug().
					Str("m", sm).
					Str("user", user).
					Msg("sending message")

				err := conn.WriteMessage(websocket.TextMessage, []byte(sm))
				if err != nil {
					log.Warn().
						Err(err).
						Str("user", user).
						Msg("failed to send message")
				}
			}

			sendMsg("notice login-success=" + user)
			break
		case "list-sites":
			// fetch existing sites for this user
			sites, err := listSites(pg, user)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Msg("couldn't fetch sites for user")
				sendMsg("notice error=" + err.Error())
				continue
			}
			sitesstr := make([]string, len(sites))
			for i, s := range sites {
				sitesstr[i] = strconv.Itoa(s.Id) + "=" + s.Subdomain
			}
			sendMsg("sites " + strings.Join(sitesstr, ","))
			break
		case "create-site":
			subdomain := m[1]
			id, err := createSite(pg, user, subdomain)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Str("subdomain", subdomain).
					Msg("couldn't create site")
				sendMsg("notice error=" + err.Error())
				continue
			}
			sendMsg("notice create-site-success=" + strconv.Itoa(id))
			break
		case "enter-site":
			id, err := strconv.Atoi(m[1])
			if err != nil {
				sendMsg("notice error=couldn't convert '" + m[1] + "' into a numeric id.")
				continue
			}
			site, err := fetchSite(pg, user, id)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Int("site", id).
					Msg("couldn't fetch site")
				sendMsg("notice error=" + err.Error())
				continue
			}

			sendSite(sendMsg, site)
			break
		case "add-source":
			siteId, err := strconv.Atoi(m[1])
			if err != nil {
				sendMsg("notice error=couldn't convert '" + m[1] + "' into a numeric id.")
				continue
			}

			site, err := addSource(pg, user, siteId)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Int("site", siteId).
					Msg("couldn't add source")
				sendMsg("notice error=" + err.Error())
				continue
			}

			sendSite(sendMsg, site)
			break
		case "update-source":
			spl := strings.SplitN(m[1], " ", 2)
			sourceId, err := strconv.Atoi(spl[0])
			if err != nil {
				sendMsg("notice error=couldn't convert '" + spl[0] + "' into a numeric id.")
				continue
			}
			source := Source{
				Id: sourceId,
			}
			err = json.Unmarshal([]byte(spl[1]), &source)
			if err != nil {
				log.Error().
					Err(err).
					Int("source", source.Id).
					Msg("couldn't parse source json")
				sendMsg("notice error=" + err.Error())
				continue
			}

			site, err := updateSource(pg, user, source)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Int("source", source.Id).
					Msg("couldn't update source")
				sendMsg("notice error=" + err.Error())
				continue
			}

			sendSite(sendMsg, site)
			break
		case "remove-source":
			sourceId, err := strconv.Atoi(m[1])
			if err != nil {
				sendMsg("notice error=couldn't convert '" + m[1] + "' into a numeric id.")
				continue
			}

			site, err := removeSource(pg, user, sourceId)
			if err != nil {
				log.Error().
					Err(err).
					Str("user", user).
					Int("source", sourceId).
					Msg("couldn't remove source")
				sendMsg("notice error=" + err.Error())
				continue
			}

			sendSite(sendMsg, site)
			break
		default:
			log.Warn().
				Str("message", m[0]).
				Msg("invalid message kind")
		}
	}
}

func sendSite(sendMsg func(string), site Site) {
	jsite, err := json.Marshal(site)
	if err != nil {
		log.Error().
			Err(err).
			Int("site", site.Id).
			Msg("couldn't jsonify site")
		sendMsg("notice error=" + err.Error())
	}

	sendMsg("site " + string(jsite))
}

func notLoggedNotify(conn *websocket.Conn, userch chan string) {
	timeout := make(chan string, 1)
	go func() {
		time.Sleep(4 * time.Second)
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
