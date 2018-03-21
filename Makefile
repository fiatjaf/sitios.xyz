all: elm.js bundle.js sitios
client: elm.js bundle.js

bundle.js: client/app.js
	cd client && ./node_modules/.bin/browserifyinc -vd app.js -o ../bundle.js

elm.js: client/Main.elm
	cd client && elm make --yes Main.elm --output ../elm.js

sitios: *.go
	go build

run:
	ag --go -l | entr -r fish -c 'make sitios; and godotenv ./sitios'
