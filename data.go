package main

import (
	"github.com/jmoiron/sqlx"
	"github.com/jmoiron/sqlx/types"
)

type Site struct {
	Id        int            `db:"id" json:"id"`
	Subdomain string         `db:"subdomain" json:"subdomain"`
	Data      types.JSONText `db:"data" json:"data"`
	Sources   types.JSONText `db:"sources" sources:"json"`
}

type Source struct {
	Id        int    `json:"id"`
	Provider  string `json:"provider"`
	Reference string `json:"reference"`
	Root      string `json:"root"`
}

func listSites(pg *sqlx.DB, user string) (sites []Site, err error) {
	err = pg.Select(&sites, `
SELECT id, subdomain
FROM sites
WHERE owner = $1
    `, user)
	return
}

func createSite(pg *sqlx.DB, user, subdomain string) (id int, err error) {
	err = pg.Get(&id, `
INSERT INTO sites (owner, subdomain) VALUES ($1, $2)
ON CONFLICT (subdomain) DO NOTHING
RETURNING id
    `, user, subdomain)
	return
}

func fetchSite(pg *sqlx.DB, user string, id int) (site Site, err error) {
	err = pg.Get(&site, `
SELECT
  id, subdomain, data,
  ( SELECT coalesce(json_agg(row_to_json(source)), '[]'::json)
    FROM (
      SELECT id, provider, reference, root
      FROM sources WHERE sources.site = sites.id
    )source
  ) AS sources
FROM sites WHERE owner = $1 AND id = $2
    `, user, id)
	return
}
