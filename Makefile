all: elm.js bundle.js sitios
client: elm.js bundle.js

bundle.js: client/app.js
	cd client && \
      godotenv -f ../.env ./node_modules/.bin/browserifyinc -t envify -vd app.js -o ../bundle.js

elm.js: client/*.elm
	npm run build-elm

sitios: *.go
	go build

run:
	ag --ignore bundle.js --ignore elm.js -l | entr -r fish -c 'make; and godotenv ./sitios'
