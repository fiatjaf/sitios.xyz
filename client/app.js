/* global Elm */

let token = location.search.slice(1).split('&')
  .map(kv => kv.split('='))
  .filter(([k, v]) => k === 'token')
  .map(([k, v]) => v)[0]

window.history.replaceState('', '', '/')

if (token) {
  localStorage.setItem('token', token)
}

var app = Elm.Main.embed(document.querySelector('main'), {
  token: token || localStorage.getItem('token'),
  ws: location.protocol.replace('http', 'ws') + location.host + '/ws'
})

app.ports.external.subscribe(url => {
  location.href = url + '?redirect_uri=' + location.href
})

// dropbox

