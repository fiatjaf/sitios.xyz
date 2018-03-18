package main

import (
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"

	"github.com/a8m/mark"
)

func publish(site Site) error {
	dirname, err := ioutil.TempDir("", "sitios")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dirname)

	var sources []Source
	err = site.Sources.Unmarshal(&sources)
	if err != nil {
		return err
	}

	for _, source := range sources {
		prefix := filepath.Join(dirname, source.Root)
		err = providers[source.Provider](prefix, source.Reference)
		if err != nil {
			return err
		}
	}

	err = ensureEmptyBucket(site.Subdomain + ".sitios.xyz")
	if err != nil {
		return err
	}

	err = uploadFilesToBucket(site.Subdomain+".sitios.xyz", dirname)
	if err != nil {
		return err
	}

	err = setupSubdomainDNS(site.Subdomain)
	if err != nil {
		return err
	}

	return nil
}

var providers = map[string]func(string, string) error{
	"url:markdown": func(prefix string, url string) error {
		btext, err := fetchText(url)
		if err != nil {
			return err
		}
		html := mark.Render(string(btext))
		return ioutil.WriteFile(prefix, []byte(html), 0666)
	},
	"url:html": func(prefix string, url string) error {
		bhtml, err := fetchText(url)
		if err != nil {
			return err
		}
		return ioutil.WriteFile(prefix, bhtml, 0666)
	},
}

func fetchText(url string) (btext []byte, err error) {
	res, err := http.Get(url)
	if err != nil {
		return
	}
	defer res.Body.Close()

	btext, err = ioutil.ReadAll(res.Body)
	if err != nil {
		return
	}
	return
}
