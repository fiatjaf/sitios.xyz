package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"text/template"
)

type GenerateContext struct {
	Globals map[string]interface{}
	Sources []Source
}

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

	// generate the generate.js file to be passed to sitio
	ctx := GenerateContext{
		Globals: map[string]interface{}{
			"rootURL":     "https://" + site.Subdomain + ".sitios.xyz",
			"name":        "unnamed",
			"description": "~",
			"nav":         []map[string]string{},
			"aside":       "",
			"footer":      "",
			"includes":    []string{},
		},
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
	cmd := exec.Command("node_modules/.bin/sitio",
		filepath.Join(dirname, "generate.js"),
		"--body=body.js",
		"--helmet=head.js",
		"--target-dir="+filepath.Join(dirname, "_site"),
	)
	cmd.Dir = "skeleton"
	out, err := cmd.CombinedOutput()
	fmt.Printf(string(out))
	if err != nil {
		return err
	}

	// send files to s3
	err = ensureEmptyBucket(site.Subdomain + ".sitios.xyz")
	if err != nil {
		return err
	}

	err = uploadFilesToBucket(site.Subdomain+".sitios.xyz", filepath.Join(dirname, "_site"))
	if err != nil {
		return err
	}

	// make https work by explicit adding a CNAME to cloudflare
	err = setupSubdomainDNS(site.Subdomain)
	if err != nil {
		return err
	}

	return nil
}