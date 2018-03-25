package main

import (
	"os"
	"strings"

	"github.com/cloudflare/cloudflare-go"
)

var cf, _ = cloudflare.New(
	os.Getenv("CLOUDFLARE_KEY"),
	os.Getenv("CLOUDFLARE_EMAIL"),
)

var zoneId, _ = cf.ZoneIDByName(mainHostname)

func setupSubdomainDNS(subdomain string) error {
	log.Debug().Str("CNAME", subdomain).Msg("setting record on cloudflare.")
	_, err := cf.CreateDNSRecord(zoneId, cloudflare.DNSRecord{
		Type:    "CNAME",
		Name:    subdomain,
		Content: "s3-website-us-east-1.amazonaws.com",
		Proxied: true,
	})
	if err != nil {
		if strings.Contains(err.Error(), "already exists") {
			return nil
		}
		return err
	}

	return nil
}

func removeSubdomainDNS(domain string) error {
	log.Debug().Str("domain", domain).Msg("removing record from cloudflare.")
	recs, err := cf.DNSRecords(zoneId, cloudflare.DNSRecord{
		Name: domain,
	})
	if err != nil {
		return err
	}

	if len(recs) == 0 {
		return nil
	}

	rec := recs[0]
	return cf.DeleteDNSRecord(zoneId, rec.ID)
}
