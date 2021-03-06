module Source exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue, onCheck)
import Dict exposing (Dict, get)
import Tuple exposing (first, second)
import List exposing (head)
import String exposing (toInt)
import Json.Decode as D
import Json.Encode as E
import Maybe exposing (withDefault)

type alias Source =
  { id : Int
  , provider : String
  , root : String
  , data : Dict String E.Value
  }

sourceDecoder = D.map4 Source
  (D.field "id" D.int)
  (D.field "provider" D.string)
  (D.field "root" D.string)
  (D.field "data" (D.dict D.value))

sourceEncoder source =
  E.object
    [ ("id", E.int source.id)
    , ("provider", E.string source.provider)
    , ("root", E.string source.root)
    , ("data", E.object <| Dict.toList source.data)
    ]

type Msg
  = EditRoot String
  | EditProvider String
  | SaveSource
  | RemoveSource
  | LeaveSource
  | EditSourceDataValue String E.Value


viewSource : Source -> Html Msg
viewSource source =
  div [ id "source" ]
    [ button [ class "close", onClick LeaveSource ] [ text "close" ]
    , label [ class "root" ]
      [ text "Root:"
      , input [ value source.root, onInput EditRoot ] []
      ]
    , hr [] []
    , label [ class "provider" ]
      [ text "Provider:"
      , select [ on "change" (D.map EditProvider targetValue) ]
        <| List.map
          ( \(name, _) ->
            option [ selected <| source.provider == name ] [ text name ]
          )
        <| providers
      ]
    , source.data |>
      ( providers
        |> List.filter (first >> (==) source.provider)
        |> List.map second
        |> head
        |> withDefault (always <| text "")
      )
    , hr [] []
    , div [ class "delete-save" ]
      [ button [ onClick RemoveSource ] [ text "Delete" ]
      , button [ onClick SaveSource ] [ text "Save" ]
      ]
    ]

providers : List (String, Dict String E.Value -> Html Msg)
providers =
  [ ( "url:html", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Give a URL containing HTML, like "
        , a [ href "https://gist.github.com/", target "_blank" ] [ text "a gist" ]
        , text " raw URL, and have it rendered on the desired site path."
        ]
      , label []
        [ b [] [ text "url: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "url")
          , value
            ( get "url" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p [] [ text "The URL of the HTML document that will be imported" ]
        ]
      , label []
        [ b [] [ text "full-page" ]
        , input
          [ type_ "checkbox"
          , onCheck  (E.bool >> EditSourceDataValue "full-page")
          , checked
            ( get "full-page" data
              |> Maybe.map ( D.decodeValue D.bool >> Result.toMaybe )
              |> maybeJoin
              |> withDefault False
            )
          ] []
        , p [] [ text "Does that URL contain a full HTML page (as opposite to containing just the main content)?" ]
        ]
      ]
    )
  , ( "url:markdown", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Give a URL containing Markdown, like "
        , a [ href "https://gist.github.com/", target "_blank" ] [ text "a gist" ]
        , text " raw URL, and have it rendered as an article on the desired "
        , text "site path. It may contain a "
        , a [] [ text "YAML front-matter" ]
        , text " with a "
        , code [] [ text "title" ]
        , text " parameter."
        ]
      , label []
        [ b [] [ text "url: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "url")
          , value
            ( get "url" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p [] [ text "The URL of the Markdown document that will be imported" ]
        ]
      ]
    )
  , ( "medium:profile", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Given a Medium profile URL (like "
        , em [] [ text "https://medium.com/@MyName" ]
        , text "), this will render all articles on that profile as blog posts, "
        , text "each in its own sub-URL, and an index page on the root URL."
        ]
      , label []
        [ b [] [ text "profile URL: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "profileURL")
          , value
            ( get "profileURL" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p [] [ text "The profile URL. It must be a public profile." ]
        ]
      , label []
        [ b [] [ text "posts per page: " ]
        , input
          [ onInput
            ( toInt
             >> Result.withDefault 7
             >> E.int
             >> EditSourceDataValue "postsPerPage"
            )
          , value
            ( get "postsPerPage" data
              |> Maybe.map ( D.decodeValue D.int >> Result.toMaybe )
              |> maybeJoin
              |> withDefault 7
              |> toString
            )
          ] []
        , p []
          [ text "The number of entries which will appear in the index page and "
          , text "in all subsequent "
          , code [] [ text "/p/{n}" ]
          , text " pagination pages. If you just want a single page with all "
          , text "entries, set this to a very high number."
          ]
        ]
      , label []
        [ b [] [ text "excerpts: " ]
        , input
          [ type_ "checkbox"
          , onCheck (E.bool >> EditSourceDataValue "excerpts")
          , checked
            ( get "excerpts" data
              |> Maybe.map ( D.decodeValue D.bool >> Result.toMaybe )
              |> maybeJoin
              |> withDefault True
            )
          ] []
        , p []
          [ text "Check this if you want the index and pagination pages to "
          , text "show an excerpt of each article. The excerpt used will be the same "
          , text "that is used by Medium itself."
          ]
        ]
      ]
    )
  , ( "trello:list", \data ->
    let
      apiKey = 
        ( get "apiKey" data
          |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
          |> maybeJoin
          |> withDefault ""
        )
      apiKeyDefault = "ac61d8974aa86dd25f9597fa651a2ed8"
    in div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Given a Trello "
        , em [] [ text "list id" ]
        , text ", this will render all cards in that list "
        , text "(except those with names starting on "
        , code [] [ text "_" ]
        , text " or "
        , code [] [ text "#" ]
        , text ") each in its own sub-URL, and an index page on the root URL."
        ]
      , label []
        [ b [] [ text "API key: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "apiKey")
          , value apiKey
          ] []
        , p []
          [ text "If you don't know what is this, "
          , a [ onClick (EditSourceDataValue "apiKey" <| E.string apiKeyDefault) ]
            [ text "click here" ]
          , text " to use the default value."
          ]
        ]
      , label []
        [ b [] [ text "API token: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "apiToken")
          , value
            ( get "apiToken" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ text "To get an API token, visit "
          , a [ href <| "https://trello.com/1/authorize?expiration=never&scope=read&response_type=token&name=sitios.xyz&key=" ++ apiKey, target "_blank" ] [ text "this page" ]
          , text " and authorize "
          , em [] [ text "read-only" ]
          , text " access to your Trello data."
          ]
        ]
      , label []
        [ b [] [ text "id: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "id")
          , value
            ( get "id" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ text "To discover the id of any Trello list, go to "
          , a [ href "/trello-list-id", target "_blank" ] [ text "this page" ]
          , text " and paste your Trello board URL there."
          ]
        ]
      , label []
        [ b [] [ text "posts per page: " ]
        , input
          [ onInput
            ( toInt
             >> Result.withDefault 7
             >> E.int
             >> EditSourceDataValue "postsPerPage"
            )
          , value
            ( get "postsPerPage" data
              |> Maybe.map ( D.decodeValue D.int >> Result.toMaybe )
              |> maybeJoin
              |> withDefault 7
              |> toString
            )
          ] []
        , p []
          [ text "The number of entries which will appear in the index page and "
          , text "in all subsequent "
          , code [] [ text "/p/{n}" ]
          , text " pagination pages. If you just want a single page with all "
          , text "entries, set this to a very high number."
          ]
        ]
      , label []
        [ b [] [ text "excerpts: " ]
        , input
          [ type_ "checkbox"
          , onCheck (E.bool >> EditSourceDataValue "excerpts")
          , checked
            ( get "excerpts" data
              |> Maybe.map ( D.decodeValue D.bool >> Result.toMaybe )
              |> maybeJoin
              |> withDefault True
            )
          ] []
        , p []
          [ text "Check this if you want the index and pagination pages to "
          , text "show small excerpts of each post/card content."
          ]
        ]
      ]
    )
  , ( "trello:board", \data ->
    let
      apiKey =
        ( get "apiKey" data
          |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
          |> maybeJoin
          |> withDefault ""
        )
      apiKeyDefault = "ac61d8974aa86dd25f9597fa651a2ed8"
    in div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Same behavior as "
        , a [ href "https://websitesfortrello.com/", target "_blank" ]
          [ text "Websites for Trello" ]
        , text ", but embedded in a subpath of your choice. "
        , text "To mimic the behavior exactly, just set the root path to /." 
        ]
      , label []
        [ b [] [ text "API key: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "apiKey")
          , value apiKey
          ] []
        , p []
          [ text "If you don't know what is this, "
          , a [ onClick (EditSourceDataValue "apiKey" <| E.string apiKeyDefault) ]
            [ text "click here" ]
          , text " to use the default value."
          ]
        ]
      , label []
        [ b [] [ text "API token: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "apiToken")
          , value
            ( get "apiToken" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ text "To get an API token, visit "
          , a [ href <| "https://trello.com/1/authorize?expiration=never&scope=read&response_type=token&name=sitios.xyz&key=" ++ apiKey, target "_blank" ] [ text "this page" ]
          , text " and authorize "
          , em [] [ text "read-only" ]
          , text " access to your Trello data."
          ]
        ]
      , label []
        [ b [] [ text "ref: " ]
        , input
          [ onInput (E.string >> EditSourceDataValue "ref")
          , value
            ( get "ref" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p [] [ text "The URL or id or shortLink of the desired Trello board." ]
        ]
      , label []
        [ b [] [ text "posts per page: " ]
        , input
          [ onInput
            ( toInt
             >> Result.withDefault 7
             >> E.int
             >> EditSourceDataValue "postsPerPage"
            )
          , value
            ( get "postsPerPage" data
              |> Maybe.map ( D.decodeValue D.int >> Result.toMaybe )
              |> maybeJoin
              |> withDefault 7
              |> toString
            )
          ] []
        , p []
          [ text "The number of entries which will appear in the index page and "
          , text "in all subsequent "
          , code [] [ text "/p/{n}" ]
          , text " pagination pages. If you just want a single page with all "
          , text "entries, set this to a very high number."
          ]
        ]
      , label []
        [ b [] [ text "excerpts: " ]
        , input
          [ type_ "checkbox"
          , onCheck (E.bool >> EditSourceDataValue "excerpts")
          , checked
            ( get "excerpts" data
              |> Maybe.map ( D.decodeValue D.bool >> Result.toMaybe )
              |> maybeJoin
              |> withDefault True
            )
          ] []
        , p []
          [ text "Check this if you want the index and pagination pages to "
          , text "show small excerpts of each post/card content."
          ]
        ]
      ]
    )
  , ( "evernote:note", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Given an Evernote "
        , em [] [ text "shared note URL" ]
        , text ", this will render its contents on the desired path as an article."
        ]
      , label []
        [ b [] [ text "url:" ]
        , input
          [ onInput (E.string >> EditSourceDataValue "url")
          , value
            ( get "url" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ a
            [ href "https://help.evernote.com/hc/en-us/articles/209005417-Share-notes"
            , target "_blank"
            ] [ text "Get a public link to a note" ]
            , text ", then paste it here."
          ]
        ]
      ]
    )
  , ( "dropbox:file", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Given a Dropbox "
        , em [] [ text "shared file URL" ]
        , text " to an HTML or Markdown file, this will render its contents "
        , text " as an article."
        ]
      , label []
        [ b [] [ text "url:" ]
        , input
          [ onInput (E.string >> EditSourceDataValue "url")
          , value
            ( get "url" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ a
            [ href "https://www.dropbox.com/help/files-folders/share-file-or-folder"
            , target "_blank"
            ] [ text "Get a read-only link to a Dropbox file" ]
            , text ", then paste it here."
          ]
        ]
      ]
    )
  , ( "dropbox:folder", \data -> div [ class "provider-data" ]
      [ p [ class "explanation" ]
        [ text "Given a Dropbox "
        , em [] [ text "shared folder URL" ]
        , text ", this will render the files inside it as a list of articles. "
        , text "HTML and Markdown files will be rendered as normal articles, "
        , text "other files will be links to the original file on Dropbox."
        ]
      , label []
        [ b [] [ text "url:" ]
        , input
          [ onInput (E.string >> EditSourceDataValue "url")
          , value
            ( get "url" data
              |> Maybe.map ( D.decodeValue D.string >> Result.toMaybe )
              |> maybeJoin
              |> withDefault ""
            )
          ] []
        , p []
          [ a
            [ href "https://www.dropbox.com/help/files-folders/share-file-or-folder"
            , target "_blank"
            ] [ text "Get a read-only link to a Dropbox folder" ]
            , text ", then paste it here."
          ]
        ]
      ]
    )
  ]

maybeJoin : Maybe (Maybe a) -> Maybe a
maybeJoin mx =
  case mx of
    Just x -> x
    Nothing -> Nothing
