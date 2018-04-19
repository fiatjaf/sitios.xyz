all: sitios client other
client: static/elm.js static/bundle.js
other: static/onboard.css static/onboard-trello.js

static/bundle.js: client/app.js
	cd client && \
      godotenv -f ../.env ./node_modules/.bin/browserifyinc -t envify -vd app.js -o ../static/bundle.js

static/elm.js: client/*.elm
	cd client && elm make --yes Main.elm --output ../static/elm.js && cd -

sitios: *.go
	go build

static/onboard-trello.js: misc/onboard-trello.js
	cd misc && \
      godotenv -f ../.env ./node_modules/.bin/browserifyinc -t envify -vd onboard-trello.js -o ../static/onboard-trello.js
static/onboard.css: misc/onboard.styl
	./misc/node_modules/.bin/stylus < misc/onboard.styl > static/onboard.css

run:
	ag --ignore-dir static -l | entr -r fish -c 'make; and godotenv ./sitios'
