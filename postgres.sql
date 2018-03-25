CREATE TABLE sites (
  id serial PRIMARY KEY,
  owner text,
  domain text UNIQUE,
  data jsonb NOT NULL DEFAULT '{
    "favicon": "https://lorempixel.com/56/56/",
    "name": "",
    "description": "",
    "aside": "",
    "footer": "",
    "includes": [],
    "nav": [{
      "txt": "Home",
      "url": "/"
    }]
  }'
);

CREATE TABLE sources (
  id serial PRIMARY KEY,
  site int REFERENCES sites (id),
  provider text NOT NULL, -- trello:card, trello:board, trello:list,
                          -- url:html, url:markdown
  root text NOT NULL -- where in the site this will appear: '/', '/posts' etc.
  data jsonb NOT NULL DEFAULT '{}' -- anything the providers may need
);
