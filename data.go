package main

import (
	"github.com/jmoiron/sqlx"
	"github.com/jmoiron/sqlx/types"
)

type Site struct {
	Id        int            `db:"id" json:"id"`
	Subdomain string         `db:"subdomain" json:"subdomain"`
	Data      types.JSONText `db:"data" json:"data"`
	Sources   types.JSONText `db:"sources" json:"sources"`
}

type Source struct {
	Id        int                    `json:"id"`
	Provider  string                 `json:"provider"`
	Reference string                 `json:"reference"`
	Root      string                 `json:"root"`
	Data      map[string]interface{} `json:"data"`
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

func deleteSite(pg *sqlx.DB, user string, id int) (err error) {
	_, err = pg.Exec(`
WITH tsite AS ( SELECT id FROM sites WHERE owner = $1 AND id = $2 ),
     sdel AS ( DELETE FROM sources WHERE site = (SELECT id FROM tsite) )
DELETE FROM sites WHERE id = (SELECT id FROM tsite)
    `, user, id)
	return
}

func fetchSite(pg *sqlx.DB, user string, id int) (site Site, err error) {
	err = pg.Get(&site, `
SELECT 
  id, subdomain, data,
  ( SELECT coalesce(json_agg(row_to_json(source)), '[]'::json)
    FROM (
      SELECT id, provider, reference, root, data
      FROM sources WHERE sources.site = sites.id
    )source
  ) AS sources
FROM sites WHERE owner = $1 AND id = $2
    `, user, id)
	return
}

func addSource(pg *sqlx.DB, user string, siteId int) (site Site, err error) {
	_, err = pg.Exec(`
INSERT INTO sources (site, provider, reference, root)
SELECT sites.id, '', '', '' FROM sites WHERE owner = $1 AND id = $2
    `, user, siteId)
	if err != nil {
		return
	}
	return fetchSite(pg, user, siteId)
}

func updateSource(pg *sqlx.DB, user string, source Source) (site Site, err error) {
	var siteId int
	err = pg.Get(&siteId, `
WITH target AS (
  SELECT sources.id AS source_id, sites.id AS site_id FROM sources
  INNER JOIN sites ON sources.site = sites.id
  WHERE sites.owner = $1 AND sources.id = $2
)
UPDATE sources SET root=$3, provider=$4, reference=$5
WHERE id = (SELECT source_id FROM target)
RETURNING (SELECT site_id FROM target)
    `, user, source.Id, source.Root, source.Provider, source.Reference)
	if err != nil {
		return
	}
	return fetchSite(pg, user, siteId)
}

func removeSource(pg *sqlx.DB, user string, sourceId int) (site Site, err error) {
	var siteId int
	err = pg.Get(&siteId, `
WITH target AS (
  SELECT sources.id AS source_id, sites.id AS site_id FROM sources
  INNER JOIN sites ON sources.site = sites.id
  WHERE sites.owner = $1 AND sources.id = $2
)
DELETE FROM sources WHERE id = (SELECT source_id FROM target)
RETURNING (SELECT site_id FROM target)
    `, user, sourceId)
	if err != nil {
		return
	}
	return fetchSite(pg, user, siteId)
}
