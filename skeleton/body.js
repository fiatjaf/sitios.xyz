const h = require('react-hyperscript')
const md = require('markdown-it')({
  html: true,
  linkify: true,
  breaks: true,
  typographer: true
})

module.exports = props => {
  return [
    h('header', {key: 'header', role: 'banner'}, [
      props.global.header ? h('img', {src: props.global.header}) : '',
      h('h1', [
        h('a', {title: props.global.name, href: '/'}, props.global.name)
      ]),
      h('aside', {
        dangerouslySetInnerHTML: {
          __html: props.global.description
            ? md.render(props.global.description)
            : ''
        }
      })
    ]),
    h('nav', {key: 'nav'}, [
      h('ul', props.global.nav.map(ni =>
        h('li', {key: ni.url}, [
          h('a', {href: ni.url}, ni.txt)
        ])
      ))
    ]),
    h('main', {key: 'main'}, props.children),
    h('aside', {
      key: 'aside',
      dangerouslySetInnerHTML: {__html: md.render(props.global.aside)}
    }),
    h('footer', {
      key: 'footer',
      role: 'contentinfo',
      dangerouslySetInnerHTML: {__html: md.render(props.global.footer)}
    })
  ].concat(
    props.global.includes.filter(isJS)
      .map(src => h('script', {src, key: src}))
  ).concat(
    props.global.justhtml ? [] : h('script', {key: 'bundle', src: '/bundle.js'})
  )
}

function isJS (url) {
  return url.split('?')[0]
    .slice(-3) === '.js'
}
