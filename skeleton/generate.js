const path = require('path')
const {init, end, generatePage} = require('sitio')
const parallel = require('run-parallel')

const plugins = {
  'url:html': 'sitio-url',
  'url:markdown': 'sitio-url'
}

init({{ json .Globals }})

parallel(
  {{ json .Sources }}
    .map(({provider, reference, root}) => function () {
      let plugin = plugins[provider]

      let gen = function (pathsuffix, component, props) {
        generatePage(
          path.join(path.join(root, pathsuffix)),
          path.join('node_modules', plugin, component),
          props
        )
      }
      require(plugin)(gen, reference)
    }),
  end
)
