package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/gorilla/websocket"
)

type GenerateContext struct {
	Globals map[string]interface{}
	Sources []Source
}

func publish(site Site, conn *websocket.Conn) error {
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

	var globals map[string]interface{}
	err = site.Data.Unmarshal(&globals)
	if err != nil {
		return err
	}
	globals["rootURL"] = "https://" + site.Domain

	// generate the generate.js file to be passed to sitio
	log.Debug().Str("domain", site.Domain).Msg("generating generate.js")
	ctx := GenerateContext{
		Globals: globals,
		Sources: sources,
	}

	t := template.New("generate.js")
	t.Funcs(map[string]interface{}{
		"json": func(v interface{}) (string, error) {
			b, err := json.Marshal(v)
			return string(b), err
		},
	})
	t, err = t.ParseFiles("skeleton/generate.js")
	if err != nil {
		return err
	}

	generateFile, err := os.Create(filepath.Join(dirname, "generate.js"))
	if err != nil {
		return err
	}
	err = t.Execute(generateFile, ctx)
	if err != nil {
		return err
	}

	// run the generate.js file
	log.Debug().Msg("generating site.")
	cmd := exec.Command("node_modules/.bin/sitio",
		filepath.Join(dirname, "generate.js"),
		"--body=body.js",
		"--helmet=head.js",
		"--target-dir="+filepath.Join(dirname, "_site"),
	)
	cmd.Dir = "skeleton"
	cmd.Stdout = logproxy{conn}
	cmd.Stderr = logproxy{conn}
	err = cmd.Run()
	if err != nil {
		return err
	}

	// send files to s3
	err = ensureBucket(site.Domain)
	if err != nil {
		return err
	}

	err = uploadFilesToBucket(site.Domain, filepath.Join(dirname, "_site"))
	if err != nil {
		return err
	}

	if strings.HasSuffix(site.Domain, mainHostname) {
		// make https work by explicit adding a CNAME to cloudflare
		err = setupSubdomainDNS(
			strings.TrimSuffix(site.Domain, "."+mainHostname),
		)
		if err != nil {
			return err
		}
	}

	return nil
}

type logproxy struct {
	conn *websocket.Conn
}

func (l logproxy) Write(p []byte) (n int, err error) {
	l.conn.WriteMessage(websocket.TextMessage, p)
	// fmt.Print(string(p))
	return len(p), nil
}
