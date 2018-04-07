const path = require('path')
const {init, end, generatePage, plug, postprocess, copyStatic} = require('sitio')

const plugins = {
  'url:html': 'sitio-url',
  'url:markdown': 'sitio-url',
  'trello:list': 'sitio-trello/list',
  'trello:board': 'sitio-trello/board',
  'evernote:note': 'sitio-evernote/note',
  'dropbox:file': 'sitio-dropbox/file',
  'dropbox:folder': 'sitio-dropbox/folder'
}

async function main (globals, sources) {
  await init(globals)

  for (let i = 0; i < sources.length; i++) {
    let {provider, root, data} = sources[i]

    let pluginName = plugins[provider]
    if (!pluginName) return
  
    try {
      await plug(pluginName, root, data)
    } catch (err) {
      console.log('error running source', pluginName, 'on', root, 'with', data, err)
      process.exit(1)
      return
    }
  }

  postprocess('sitio-error')

  await copyStatic([
    '**/*.*(jpeg|jpg|png|svg|txt)'
  ])

  if (!globals.justhtml) {
    await end()
  }
}

try {
  main(
    {{ json .Globals }},
    {{ json .Sources }}
  )
} catch (err) {
  console.log('error generating site', err)
}
