/* global fetch */

const React = require('react')
const render = require('react-dom').render
const h = require('react-hyperscript')
const Trello = require('trello-web')
const Select = require('react-select').default

const trello = new Trello(process.env.TRELLO_KEY)

class Main extends React.Component {
  constructor () {
    super()

    this.state = {
      step: 0,
      boards: [],
      lists: [],
      chosenBoard: '',
      chosenList: '',
      site: null
    }

    this.steps = [
      () => (
        h('form', {
          onSubmit: e => {
            e.preventDefault()

            trello.auth({
              expiration: 'never',
              scope: {read: true},
              name: 'sitios.xyz'
            })
              .then(() =>
                trello.get('/1/members/me/boards', {
                  filter: 'open',
                  fields: 'id,name,starred'
                })
              )
              .then(boards => {
                this.setState({
                  step: this.state.step + 1,
                  boards: boards
                    .sort((a, b) => [a.starred, a.name] < [b.starred, b.name] ? 1 : -1)
                })
              })
              .catch(e => {
                this.setState({error: 'error fetching trello boards: ' + e.message})
                console.log('error fetching trello boards', e)
              })
          }
        }, [
          h('h1', "You're 3 steps away from generating a blog with content from a Trello list. If you want to proceed, press 'GO' to authorize with your Trello account."),
          h('button', 'GO')
        ])
      ),
      () => (
        h('form', {
          onSubmit: e => {
            e.preventDefault()

            trello.get(`/1/boards/${this.state.chosenBoard}/lists/open`)
              .then(lists => {
                this.setState({
                  lists,
                  step: this.state.step + 1
                })
              })
              .catch(e => {
                this.setState({error: 'error fetching trello lists: ' + e.message})
                console.log('failed to fetch lists', e)
              })
          }
        }, [
          h('h1', 'In which of these boards is the list you want to use?'),
          h(Select, {
            value: this.state.chosenBoard,
            onChange: opt => {
              this.setState({chosenBoard: opt.value})
            },
            options: this.state.boards
              .map(b => ({value: b.id, label: b.name}))
          }),
          h('button', 'OK')
        ])
      ),
      () => (
        h('form', {
          onSubmit: e => {
            e.preventDefault()
            this.setState({
              step: this.state.step + 1
            })
            Promise.all([
              trello.get(`/1/members/me`),
              trello.get(`/1/lists/${this.state.chosenList}`)
            ])
              .then(([me, list]) => {
                console.log(list)
                console.log(me)

                return fetch(`/trello/instant-site`, {
                  method: 'POST',
                  body: JSON.stringify({
                    domain: list.id.slice(0, 5) + '.' + process.env.MAIN_HOSTNAME,
                    data: {
                      name: `${me.username}'s site`,
                      description: '',
                      header: '',
                      favicon: `https://trello-avatars.s3.amazonaws.com/${me.avatarHash}/170.png`,
                      aside: `${me.avatarHash ? `![](https://trello-avatars.s3.amazonaws.com/${me.avatarHash}/170.png)` : null}

Hello, I'm ${me.fullName}!

${me.bio}`,
                      footer: `A demo site created by [${me.username}](https://trello.com/${me.username}) on sitios.xyz, ${(new Date()).getFullYear()}.`,
                      includes: [
                        'https://cdn.rawgit.com/fiatjaf/classless/e332d9f7/themes/zen/theme.css'
                      ],
                      nav: [
                        {url: '/', txt: 'Posts'},
                        {url: `https://trello.com/${me.username}`, txt: 'About'}
                      ]
                    },
                    sources: [{
                      provider: 'trello:list',
                      root: '/',
                      data: {
                        id: list.id,
                        apiKey: trello.key,
                        apiToken: trello.token
                      }
                    }]
                  })
                })
                  .then(r => r.json())
                  .then(site => {
                    this.setState({
                      step: this.state.step + 1,
                      site
                    })
                  })
              })
              .catch(e => {
                this.setState({error: 'failed deploying your site: ' + e.message})
                console.log('failed deploying your site', e)
              })
          }
        }, [
          h('h1', 'Select the list you want to use'),
          h(Select, {
            value: this.state.chosenList,
            onChange: opt => {
              this.setState({chosenList: opt.value})
            },
            options: this.state.lists
              .map(b => ({value: b.id, label: b.name}))
          }),
          h('button', 'OK')
        ])
      ),
      () => (
        h('form', [
          h('h1', "Wait, we're building your site...")
        ])
      ),
      () => (
        h('form', [
          h('h1', [
            'Your site was built and is waiting for you on ',
            h('a', {
              target: '_blank',
              href: 'http://' + this.state.site.domain
            }, this.state.site.domain),
            '.'
          ]),
          h('h1', [
            'To claim control over it, login on ',
            h('a', {target: '_blank', href: '/'}, 'sitios.xyz'),
            ' using your Trello account.'
          ]),
          h('h1', [
            h('small', 'This site is temporary and may be deleted at any time. Use it as a model to create a site with a meaningful name.')
          ])
        ])
      )
    ]

    this.error = () => (
      h('form', [
        h('h1', 'Sorry. An error has ocurred.'),
        h('p', h('code', this.state.error)),
        h('p', [
          'Please try creating your site from scratch on ',
          h('a', {href: 'https://sitios.xyz/'}, 'https://sitios.xyz/'),
          '. '
        ])
      ])
    )
  }

  render () {
    return [
      h('#form', {key: 'form'}, [
        this.steps[this.state.step]()
      ])
    ]
  }
}

render(
  React.createElement(Main),
  document.getElementById('root')
)
