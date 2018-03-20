const h = require('react-hyperscript')
const md = require('markdown-it')({
  html: true,
  linkify: true,
  breaks: true,
  typographer: true
})

module.exports = props => [
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
        h('a', {href: ni.url}, ni.text)
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
  h('script', {key: 'bundle', src: '/bundle.js'})
)
