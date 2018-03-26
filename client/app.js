/* global Elm */

const haikunate = require('haikunator-porreta')

let token = location.search.slice(1).split('&')
  .map(kv => kv.split('='))
  .filter(([k, v]) => k === 'token')
  .map(([k, v]) => v)[0]

window.history.replaceState('', '', '/')

if (token) {
  localStorage.setItem('token', token)
}

if (token || localStorage.getItem('token')) {
  // we're logged in. remove landing page stuff.
  document.body.removeChild(document.querySelector('article'))
  document.body.removeChild(document.querySelector('footer'))
}

var app = Elm.Main.embed(document.querySelector('main'), {
  token: token || localStorage.getItem('token'),
  ws: location.protocol.replace('http', 'ws') + location.host + '/ws',
  main_hostname: process.env.MAIN_HOSTNAME
})

app.ports.external.subscribe(url => {
  location.href = url + '?redirect_uri=' + location.href
})

app.ports.logout.subscribe(() => {
  localStorage.removeItem('token')
})

app.ports.generate_subdomain.subscribe(() => {
  app.ports.generated_subdomain.send(haikunate())
})
