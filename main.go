package main

import (
	"net/http"
	"os"
	"strings"

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

	for {
		typ, bm, err := conn.ReadMessage()
		if err != nil || typ != websocket.TextMessage {
			log.Error().
				Err(err).
				Msg("error reading message")
			break
		}
		sm := string(bm)

		log.Debug().
			Str("message", sm).
			Msg("read message")

		m := strings.Split(sm, " ")

		switch m[0] {
		case "login":
			user, err = acd.VerifyAuth(m[1])
			if err != nil {
				log.Error().
					Err(err).
					Str("token", m[1]).
					Msg("failed to verify auth token")
				sendMsg(conn, "notice error="+err.Error())
				continue
			}
			sendMsg(conn, "notice login-success="+user)
			break
		case "":
			break
		}
	}
}

func sendMsg(conn *websocket.Conn, sm string) {
	log.Debug().
		Str("message", sm).
		Msg("sending message")

	err := conn.WriteMessage(websocket.TextMessage, []byte(sm))
	if err != nil {
		log.Warn().
			Err(err).
			Msg("failed to send message to connection")
	}
}
