package main

import (
	"html/template"
	"net/http"
	"os"
)

var trelloKey = os.Getenv("TRELLO_KEY")
var trelloListIdTemplates = template.Must(template.ParseFiles("templates/trello-list-id.html"))

func trelloListIdHandle(w http.ResponseWriter, r *http.Request) {
	err := trelloListIdTemplates.Execute(w, map[string]string{
		"trelloKey":  trelloKey,
		"serviceURL": serviceURL,
	})
	if err != nil {
		log.Print(err)
	}
}
