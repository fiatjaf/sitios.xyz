package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/a8m/mark"
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
	if desc, ok := globals["description"].(string); ok {
		globals["description"] = mark.Render(desc)
	} else {
		globals["description"] = ""
	}
	if aside, ok := globals["aside"].(string); ok {
		globals["aside"] = mark.Render(aside)
	} else {
		globals["aside"] = ""
	}
	if footer, ok := globals["footer"].(string); ok {
		globals["footer"] = mark.Render(footer)
	} else {
		globals["footer"] = ""
	}

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
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		return err
	}
	log.Debug().Msg("site generated successfully.")
	if conn != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("Site generated successfully."))
	}

	// send files to s3
	if conn != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("Now publishing..."))
	}
	log.Debug().Msg("uploading to s3...")
	err = ensureBucket(site.Domain)
	if err != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("Error creating S3 bucket: "+err.Error()))
		return err
	}

	err = uploadFilesToBucket(site.Domain, filepath.Join(dirname, "_site"))
	if err != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("Error publishing to S3: "+err.Error()))
		return err
	}

	if strings.HasSuffix(site.Domain, mainHostname) {
		log.Debug().Msg("setting dns record...")
		// make https work by explicit adding a CNAME to cloudflare
		err = setupSubdomainDNS(
			strings.TrimSuffix(site.Domain, "."+mainHostname),
		)
		if err != nil {
			conn.WriteMessage(websocket.TextMessage, []byte("Error setting DNS records: "+err.Error()))
			return err
		}
	}

	if conn != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("Published successfully."))
	}
	return nil
}

type logproxy struct {
	conn *websocket.Conn
}

func (l logproxy) Write(p []byte) (n int, err error) {
	if l.conn != nil {
		l.conn.WriteMessage(websocket.TextMessage, p)
	}
	return len(p), nil
}
