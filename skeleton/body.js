const h = require('react-hyperscript')
const Helmet = require('react-safety-helmet').default

module.exports = props => {
  return [
    h(Helmet, {key: 'helmet'}, [
      h('meta', {charset: 'utf-8'}),
      h('meta', {httpEquiv: 'x-ua-compatible', content: 'ie: edge'}),
      h('meta', {name: 'description', content: 'Pure-CSS themes for standard HTML formats.'}),
      h('meta', {name: 'viewport', content: 'width=device-width, height=device-height, initial-scale=1.0, user-scalable=yes'}),
      h('title', props.global.name),
      h('link', {href: props.global.favicon, rel: 'shortcut icon'})
    ].concat(
      (props.global.includes || []).filter(isCSS)
        .map(href => h('link', {href, rel: 'stylesheet'}))
    )),
    h('header', {key: 'header', role: 'banner'}, [
      props.global.header ? h('img', {src: props.global.header}) : '',
      h('h1', [
        h('a', {title: props.global.name, href: '/'}, props.global.name)
      ]),
      h('aside', {
        dangerouslySetInnerHTML: {
          __html: props.global.description || ''
        }
      })
    ]),
    h('nav', {key: 'nav'}, [
      h('ul', (props.global.nav || []).map(ni =>
        h('li', {key: ni.url}, [
          h('a', {href: ni.url}, ni.txt)
        ])
      ))
    ]),
    h('main', {key: 'main'}, props.children),
    h('aside', {
      key: 'aside',
      dangerouslySetInnerHTML: {__html: props.global.aside}
    }),
    h('footer', {
      key: 'footer',
      role: 'contentinfo',
      dangerouslySetInnerHTML: {__html: props.global.footer}
    })
  ].concat(
    (props.global.includes || []).filter(isJS)
      .map(src => h('script', {src, key: src}))
  ).concat(
    props.global.justhtml ? [] : h('script', {key: 'bundle', src: '/bundle.js'})
  )
}

function isJS (url) {
  return url.split('?')[0]
    .slice(-3) === '.js'
}

function isCSS (url) {
  return url.split('?')[0]
    .slice(-4) === '.css'
}
