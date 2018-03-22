module Site exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue, onCheck)
import Dict exposing (Dict)
import Array exposing (Array)
import Json.Decode as D
import Json.Encode as E

import Source exposing (..)

type alias Site =
  { id : Int
  , subdomain : String
  , sources : List Source
  , data : SiteData
  }

emptySite = Site 0 "" [] emptySiteData

type alias SiteData =
  { favicon : String
  , name : String
  , description : String
  , nav : Array { url : String, txt: String }
  , aside : String
  , footer : String
  , includes : Array String
  }

emptySiteData = SiteData "" "" "" Array.empty "" "" Array.empty

siteDecoder = D.map4 Site
  (D.field "id" D.int)
  (D.field "subdomain" D.string)
  (D.field "sources" (D.list sourceDecoder))
  (D.field "data" siteDataDecoder)

siteDataDecoder = D.map7 SiteData
  (D.field "favicon" D.string)
  (D.field "name" D.string)
  (D.field "description" D.string)
  (D.field "nav"
    (D.array <|
      D.map2 (\url txt -> { url = url, txt = txt})
        (D.field "url" D.string)
        (D.field "txt" D.string)
    )
  )
  (D.field "aside" D.string)
  (D.field "footer" D.string)
  (D.field "includes" (D.array D.string) )

siteDataEncoder data =
  E.object
    [ ("favicon", E.string data.favicon)
    , ("name", E.string data.name)
    , ("description", E.string data.description)
    , ("includes", E.array
        <| Array.map E.string data.includes
      )
    , ("nav", E.array
        <| Array.map ( \{txt, url} ->
            E.object
              [ ("txt", E.string txt)
              , ("url", E.string url)
              ]
          )
        <| data.nav
      )
    , ("aside", E.string data.aside)
    , ("footer", E.string data.footer)
    ]

type Msg
  = EditSubdomain String
  | FinishCreatingSite
  | SiteDataAction SiteDataMsg
  | Publish
  | Delete
  | EnterSource Source
  | AddSource
  | SourceAction Int Int Source.Msg

type SiteDataMsg
  = EditName String
  | EditDescription String
  | EditFavicon String
  | EditAside String
  | EditFooter String
  | AddInclude
  | EditInclude Int String
  | RemoveInclude Int
  | AddNavItem
  | EditNavItem Int { txt : String, url : String }
  | RemoveNavItem Int
  | SaveSiteData


viewSite : Site -> Html Msg
viewSite site =
  if site.id == 0 then -- creating site
    Html.form [ onSubmit FinishCreatingSite ]
      [ label []
        [ text "Please enter a subdomain:"
        , input [ onInput EditSubdomain, value site.subdomain ] []
        ]
      , button [] [ text "Create" ]
      ]
  else div [] -- already created
    [ header []
      [ div []
        [ a [ href <| "https://" ++ site.subdomain ++ ".sitios.xyz/", target "_blank" ]
          [ text "Visit site"
          ]
        ]
      , h1 [] [ text site.subdomain ]
      , div []
        [ button [ onClick Publish ] [ text "Publish site" ]
        ]
      ]
    , hr [] []
    , div [] [ text "Data sources:" ]
    , ul []
      <| List.map
        ( \source ->
          li [ class "source" ]
            [ a [ onClick (EnterSource source) ]
              [ text <| source.root ++ " -> " ++ source.provider
              ]
            ]
        )
      <| site.sources
    , button [ onClick AddSource ] [ text "Add a new data source" ]
    , hr [] []
    , Html.map SiteDataAction (viewSiteData site.data)
    , hr [] []
    , div [ class "delete-site" ]
      [ button [ onClick Delete ] [ text "Delete site" ]
      ]
    ]

viewSiteData : SiteData -> Html SiteDataMsg
viewSiteData {name, description, favicon, aside, footer, includes, nav} =
  div [ id "site-data" ]
    [ label []
      [ text "Title: "
      , input [ value name, onInput EditName ] []
      ]
    , label []
      [ text "Description: "
      , textarea
        [ placeholder "(this field accepts Markdown)"
        , onInput EditDescription
        ] [ text description ]
      ]
    , label []
      [ text "Favicon: "
      , input [ value favicon, onInput EditFavicon ] []
      ]
    , div []
      [ div [ class "label" ]
        [ text "Navbar items: "
        , button [ onClick AddNavItem ] [ text "+" ]
        ]
      , div [ class "subitems" ]
        <| List.indexedMap
          ( \i {txt, url} ->
            div []
              [ input
                [ placeholder "Link label"
                , value txt
                , onInput (\v-> EditNavItem i {txt=v, url=url})
                ] []
              , text ": "
              , input [ placeholder "Link URL"
                , value txt
                , onInput (\v-> EditNavItem i {txt=txt, url=v})
                ] []
              , button [ onClick (RemoveNavItem i) ] [ text "×" ]
              ]
          )
        <| Array.toList nav
      ]
    , div []
      [ div [ class "label" ]
        [ text "Includes: "
        , button [ onClick AddInclude ] [ text "+" ]
        ]
      , div [ class "subitems" ]
        <| List.indexedMap
          ( \i include ->
            div []
              [ input [ value include, onInput (EditInclude i) ] []
              , button [ onClick (RemoveInclude i) ] [ text "×" ]
              ]
          )
        <| Array.toList includes
      ]
    , label []
      [ text "Aside text: "
      , textarea
        [ placeholder "(this field accepts Markdown)"
        , onInput EditAside
        ] [ text aside ]
      ]
    , label []
      [ text "Footer text: "
      , textarea
        [ placeholder "(this field accepts Markdown)"
        , onInput EditFooter
        ] [ text footer ]
      ]
    , div [ class "submit" ]
      [ button [ onClick SaveSiteData ] [ text "Save" ]
      ]
    ]

