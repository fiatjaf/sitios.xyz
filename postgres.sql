CREATE TABLE sites (
  id serial PRIMARY KEY,
  owner text,
  subdomain text UNIQUE,
  data jsonb NOT NULL DEFAULT '{}'
);

CREATE TABLE sources (
  id serial PRIMARY KEY,
  site int REFERENCES sites (id),
  provider text NOT NULL, -- trello:card, trello:board, trello:list,
                          -- url:html, url:markdown
  reference text NOT NULL, -- url, trello card id etc.
  root text NOT NULL -- where in the site this will appear: '/', '/posts' etc.
);
