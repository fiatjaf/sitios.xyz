const path = require('path')
const {init, end, generatePage, plug, copyStatic} = require('sitio')
const parallel = require('run-parallel')

const plugins = {
  'url:html': 'sitio-url',
  'url:markdown': 'sitio-url',
  'trello:list': 'sitio-trello/list',
  'evernote:note': 'sitio-evernote/note'
}

init({{ json .Globals }})

let tasks = {{ json .Sources }}.map(({provider, root, data}) => function (done) {
  let pluginName = plugins[provider]
  if (!pluginName) return

  data.ref = reference
  plug(pluginName, root, data, done)
})

parallel(
  tasks,
  (err, _) => {
    if (err) {
      console.log('error running one of the sources', err)
      return
    }

    copyStatic([
      '**/*.*(jpeg|jpg|png|svg|txt)'
    ])

    end()
  }
)
