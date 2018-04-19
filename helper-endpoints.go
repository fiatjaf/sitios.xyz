package main

import (
	"encoding/json"
	"errors"
	"html/template"
	"io/ioutil"
	"net/http"
	"os"

	"github.com/jmoiron/sqlx"
)

var trelloKey = os.Getenv("TRELLO_KEY")

var tlit = template.Must(template.ParseFiles("templates/trello-list-id.html"))

func trelloListIdHandle(w http.ResponseWriter, r *http.Request) {
	err := tlit.Execute(w, map[string]string{
		"trelloKey":  trelloKey,
		"serviceURL": serviceURL,
	})
	if err != nil {
		log.Print(err)
	}
}

var ott = template.Must(template.ParseFiles("templates/onboard-trello.html"))

func onboardTrello(w http.ResponseWriter, r *http.Request) {
	err := ott.Execute(w, map[string]string{})
	if err != nil {
		log.Print(err)
	}
}

func trelloInstantSite(pg *sqlx.DB, w http.ResponseWriter, r *http.Request) {
	var site Site
	err := json.NewDecoder(r.Body).Decode(&site)
	if err != nil {
		http.Error(w, "wrong site data: "+err.Error(), 400)
		return
	}

	var sources []Source
	err = site.Sources.Unmarshal(&sources)
	if err == nil && len(sources) == 0 {
		err = errors.New("zero sources received.")
	}
	if err != nil {
		http.Error(w, "wrong site.sources: "+err.Error(), 400)
		return
	}

	// get user to which we will associate this account: username@trello
	var data struct {
		APIKey   string `json:"apiKey"`
		APIToken string `json:"apiToken"`
	}
	err = sources[0].Data.Unmarshal(&data)
	if err != nil {
		http.Error(w, "wrong trello data: "+err.Error(), 400)
		return
	}

	log.Print(data)
	resp, err := http.Get(
		"https://api.trello.com/1/members/me?key=" + data.APIKey +
			"&token=" + data.APIToken + "&fields=username",
	)
	if resp.StatusCode >= 300 {
		body, _ := ioutil.ReadAll(resp.Body)
		err = errors.New(string(body))
	}
	if err != nil {
		http.Error(w, "trello call failed: "+err.Error(), 500)
		return
	}

	var userData struct {
		Username string `json:"username"`
	}
	err = json.NewDecoder(resp.Body).Decode(&userData)
	if err != nil {
		http.Error(w, "failed to decode trello response: "+err.Error(), 500)
		return
	}
	user := userData.Username + "@trello"

	siteId, err := createSite(pg, user, site.Domain)
	if err != nil {
		http.Error(w, "failed to create site: "+err.Error(), 500)
		return
	}

	_, err = updateSiteData(pg, user, siteId, site.Data)
	if err != nil {
		http.Error(w, "failed to update site: "+err.Error(), 500)
		return
	}

	site, err = addSource(pg, user, siteId)
	if err != nil {
		http.Error(w, "failed to add source: "+err.Error(), 500)
		return
	}

	var isources []Source
	site.Sources.Unmarshal(&isources)
	sources[0].Id = isources[0].Id
	site, err = updateSource(pg, user, sources[0])
	if err != nil {
		http.Error(w, "failed to update source: "+err.Error(), 500)
		return
	}

	// publish
	err = publish(site, nil)
	if err != nil {
		http.Error(w, "failed to publish site: "+err.Error(), 500)
		return
	}

	json.NewEncoder(w).Encode(site)
}
