const h = require('react-hyperscript')
const Helmet = require('react-helmet').default

module.exports = props =>
  h(Helmet, {
    meta: [
      {charset: 'utf-8'},
      {httpEquiv: 'x-ua-compatible', content: 'ie: edge'},
      {name: 'description', content: props.global.description || ''},
      {name: 'viewport', content: 'width=device-width, height=device-height, initial-scale=1.0, user-scalable=yes'}
    ],
    title: props.global.name,
    link: props.global.includes.filter(include => include.slice(-4) === '.css')
      .map(href => ({href, rel: 'stylesheet'}))
      .concat([{href: props.global.favicon, rel: 'shortcut icon'}]),
    script: []
  })
