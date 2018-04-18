all: static/elm.js static/bundle.js sitios
client: static/elm.js static/bundle.js

static/bundle.js: client/app.js
	cd client && \
      godotenv -f ../.env ./node_modules/.bin/browserifyinc -t envify -vd app.js -o ../static/bundle.js

static/elm.js: client/*.elm
	cd client && elm make --yes Main.elm --output ../static/elm.js && cd -

sitios: *.go
	go build

run:
	ag --ignore-dir static -l | entr -r fish -c 'make; and godotenv ./sitios'
