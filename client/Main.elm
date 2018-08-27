import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue)
import Http
import Platform.Sub as Sub
import List exposing (head, drop, singleton, filter, intersperse)
import Array exposing (set, get, append, slice, push)
import String exposing (endsWith, dropRight)
import WebSocket exposing (listen, send)
import Task
import Dict
import Json.Encode as E
import Json.Decode as D

import Ports exposing (..)
import Site exposing (..)
import Source exposing (..)

type alias Model =
  { log : List String
  , user : Maybe String
  , sites : List Site
  , site : Maybe Site
  , source : Maybe Source
  , token : Maybe String
  , ws : String
  , main_hostname : String
  , login_with : String
  }

type Msg
  = Init
  | NewMessage String
  | Response ResponseMsg
  | LoginUsing String
  | LoginWith String
  | SetLoginWith String
  | Logout
  | EnterSite Int
  | StartCreatingSite
  | GotRandomSubdomain String
  | SiteAction Site.Msg

type ResponseMsg
  = GotIdentity String
  | GotCreatedSite Int
  | GotSitesList (List Site)
  | GotSite Site
  | GotDeletedSite Int ()
  | GotPublishedSite Int ()
  | GotError Http.Error

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  let
    authHeader : List Http.Header
    authHeader = model.token
      |> Maybe.map (\token -> [ Http.header "Authorization" ("Basic " ++ token) ])
      |> Maybe.withDefault []
    handleResponse : (a -> ResponseMsg) -> Result Http.Error a -> Msg
    handleResponse handler result =
      case result of
        Err err -> Response (GotError err)
        Ok something -> Response (handler something)
    defaultRequest =
      { method = "POST"
      , headers = authHeader
      , url = ""
      , body = Http.emptyBody
      , expect = Http.expectStringResponse (\_ -> Ok ())
      , timeout = Nothing
      , withCredentials = False
      }
    whoami = 
      Http.request
        { defaultRequest
          | expect = Http.expectJson D.string
          , url = "/whoami"
        } |> Http.send (handleResponse GotIdentity)
    getSite id = 
      Http.request
        { defaultRequest
          | url = "/get-site"
          , body = Http.jsonBody (E.object [ ("id", E.int id) ])
          , expect = Http.expectJson siteDecoder
        } |> Http.send (handleResponse GotSite)
    listSites =
      Http.request
        { defaultRequest
          | url = "/list-sites"
          , expect = Http.expectJson (D.list siteDecoder)
        } |> Http.send (handleResponse GotSitesList)
    createSite domain =
      Http.request
        { defaultRequest
          | url = "/create-site"
          , body = Http.jsonBody (E.object [ ("domain", E.string domain) ])
          , expect = Http.expectJson D.int
        } |> Http.send (handleResponse GotCreatedSite)
    updateSiteData siteId data =
      Http.request
        { defaultRequest
          | url = "/update-site"
          , body = Http.jsonBody (E.object [ ("id", E.int siteId), ("data", data) ])
          , expect = Http.expectJson siteDecoder
        } |> Http.send (handleResponse GotSite)
    deleteSite siteId =
      Http.request
        { defaultRequest
          | url = "/delete-site"
          , body = Http.jsonBody (E.object [ ("id", E.int siteId) ])
        } |> Http.send (handleResponse (GotDeletedSite siteId))
    addSource siteId =
      Http.request
        { defaultRequest
          | url = "/add-source"
          , body = Http.jsonBody (E.object [ ("id", E.int siteId) ])
          , expect = Http.expectJson siteDecoder
        } |> Http.send (handleResponse GotSite)
    updateSource source =
      Http.request
        { defaultRequest
          | url = "/update-source"
          , body = Http.jsonBody (sourceEncoder source)
          , expect = Http.expectJson siteDecoder
        } |> Http.send (handleResponse GotSite)
    deleteSource id =
      Http.request
        { defaultRequest
          | url = "/delete-source"
          , body = Http.jsonBody (E.object [ ("id", E.int id) ])
          , expect = Http.expectJson siteDecoder
        } |> Http.send (handleResponse GotSite)
    publish siteId =
      Http.request
        { defaultRequest
          | url = "/publish"
          , body = Http.jsonBody (E.object [ ("id", E.int siteId) ])
        } |> Http.send (handleResponse (GotPublishedSite siteId))
  in case msg of
    Init ->
      ( model
      , case model.token of
        Just token -> 
          Cmd.batch
          [ send model.ws <| "login " ++ token
          , whoami
          , listSites
          ]
        Nothing -> Cmd.none
      )
    LoginWith account ->
      ( model
      , external <| "https://accountd.xyz/login/with/" ++ account
      )
    SetLoginWith account ->
      ( { model | login_with = account }
      , Cmd.none
      )
    LoginUsing provider -> 
      ( model
      , external <| "https://accountd.xyz/login/using/" ++ provider
      )
    Logout ->
      ( { model | user = Nothing, sites = [], source = Nothing, token = Nothing }
      , logout True
      )
    NewMessage m ->
      case m of
        "not-logged" ->
          case model.token of
            Just token ->
              ( model
              , send model.ws <| "login " ++ token
              )
            Nothing ->
              ( { model | log = "Disconnected." :: model.log }
              , Cmd.none
              )
        _ ->
          ( { model | log = m :: model.log }
          , Cmd.none
          )
    Response enc ->
      case enc of
        GotIdentity username ->
          ( { model
              | user = Just username
              , log = ("Logged in as " ++ username ++ ".") :: model.log
            }
          , Cmd.none
          )
        GotSite site ->
          ( { model | site = Just site }
          , Cmd.none
          )
        GotSitesList sites ->
          ( { model | sites = sites }
          , Cmd.none
          )
        GotCreatedSite siteId ->
          ( model
          , Cmd.batch
            [ getSite siteId
            , listSites
            ]
          )
        GotDeletedSite id _ ->
          ( { model
              | log = ("Site " ++ toString id ++ " was deleted successfully.") :: model.log
            }
          , listSites
          )
        GotPublishedSite id _ ->
          ( model
          , Cmd.none
          )
        GotError httperr ->
          let
            err = case httperr of
              Http.BadUrl err -> "BadUrl: " ++ err
              Http.Timeout -> "Timeout error."
              Http.NetworkError -> "NetworkError. Are you connected to the internet"
              Http.BadStatus {url, status, headers, body} ->
                (toString status.code) ++ ": " ++ body
              Http.BadPayload decodingErr {url, status, headers, body} ->
                decodingErr ++ " on response from " ++ url ++ ": " ++ body
          in
            ( { model | log = err :: model.log }
            , Cmd.none
            )
    EnterSite id ->
      ( { model | log = ("Entering site " ++ toString id) :: model.log }
      , getSite id
      )
    StartCreatingSite ->
      ( { model
          | log = "Waiting for domain to create site." :: model.log
          , site = Just emptySite
        }
      , generate_subdomain True
      )
    GotRandomSubdomain subd ->
      ( case model.site of 
          Nothing -> model
          Just site ->
            let nextsite =
              if site.domain /= "" then site
              else { site | domain = subd ++ "." ++ model.main_hostname }
            in { model | site = Just nextsite }
      , Cmd.none
      )
    SiteAction msg -> case model.site of
      Nothing -> ( model, Cmd.none )
      Just site -> case msg of
        EditDomain domain -> 
          ( { model | site = Just { site | domain = domain } }
          , Cmd.none
          )
        FinishCreatingSite -> 
          if site.id == 0 then
            ( { model
                | site = Nothing
                , log = ("Creating site " ++ site.domain) :: model.log
              }
            , createSite site.domain
            )
          else ( model , Cmd.none )
        SiteDataAction sdmsg ->
          let
            data = site.data
            newdata = case sdmsg of
              EditName v -> { data | name = v }
              EditHeader v -> { data | header = v }
              EditDescription v -> { data | description = v }
              EditFavicon v -> { data | favicon = v }
              EditAside v -> { data | aside = v }
              EditFooter v -> { data | footer = v }
              EditJustHTML v -> { data | justhtml = v }
              AddInclude -> { data | includes = data.includes |> push "" }
              EditInclude i v -> { data | includes = data.includes |> set i v }
              RemoveInclude i ->
                { data | includes = append
                  ( data.includes |> slice 0 i )
                  ( data.includes |> slice (i + 1) (Array.length data.includes ) )
                }
              AddNavItem -> { data | nav = data.nav |> push {txt="", url=""} }
              EditNavItem i v -> { data | nav = data.nav |> set i v }
              RemoveNavItem i ->
                { data | nav = append
                  ( data.nav |> slice 0 i )
                  ( data.nav |> slice (i + 1) (Array.length data.nav ) )
                }
              _ -> data
            newsite = { site | data = newdata }
          in
            ( { model
                | site = Just newsite
                , log =
                  case sdmsg of
                    SaveSiteData -> "Saving site." :: model.log
                    _ -> model.log
              }
            , case sdmsg of
              SaveSiteData -> updateSiteData site.id (siteDataEncoder site.data)
              _ -> Cmd.none
            )
        Publish ->
          ( { model
              | log = [ "Publishing site " ++ toString site.id ] -- cleanup all log messages
            }
          , publish site.id
          )
        Delete ->
          ( { model | log = model.log |> (::) ("Deleting site " ++ site.domain) }
          , deleteSite site.id
          )
        EnterSource source ->
          ( { model
              | source = Just source
              , log =
                ("Opening source " ++ toString source.id ++ " on " ++ source.root)
                :: model.log
            }
          , Cmd.none
          )
        AddSource ->
          ( { model
              | log = ("Creating new source on site " ++ toString site.id) :: model.log
            }
          , addSource site.id
          )
        SourceAction siteId sourceId sourcemsg ->
          case model.source of
            Nothing -> ( model, Cmd.none )
            Just source ->
              let
                nextsource = case sourcemsg of
                  EditRoot root -> Just { source | root = root }
                  EditProvider provider -> Just
                    { source
                      | provider = provider
                      , data = Dict.empty
                    }
                  LeaveSource -> Nothing
                  EditSourceDataValue key value -> Just
                    { source | data = source.data |> Dict.insert key value
                    }
                  _ -> model.source

                effect = case sourcemsg of
                  SaveSource -> updateSource source
                  RemoveSource -> deleteSource sourceId
                  _ -> Cmd.none

                nextlog = case sourcemsg of
                  LeaveSource -> ("Closing source " ++ toString source.id) :: model.log
                  SaveSource ->
                    ("Saving source " ++ toString source.id ++ " on " ++ source.root)
                    :: model.log
                  RemoveSource ->
                    ("Removing source " ++ toString source.id ++ " from " ++ source.root)
                    :: model.log
                  _ -> model.log
              in
                ( { model
                    | source = nextsource
                    , log = nextlog
                  }
                , effect
                )


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ listen model.ws NewMessage
    , generated_subdomain GotRandomSubdomain
    ]

view : Model -> Html Msg
view model =
  div []
    [ case model.user of
      Nothing ->
        div [ id "login" ]
          [ text "login using "
          , button [ onClick (LoginUsing "twitter") ] [ text "twitter" ]
          , text ", "
          , button [ onClick (LoginUsing "github") ] [ text "github" ]
          , text ", "
          , button [ onClick (LoginUsing "trello") ] [ text "trello" ]
          , span [] [ text " or " ]
          , Html.form [ onSubmit (LoginWith model.login_with) ]
            [ input [ onInput SetLoginWith, placeholder "your@email.com" ] []
            , button [] [ text "ok" ]
            ]
          ]
      Just username ->
        div [ id "main" ]
          [ div [ id "list" ] <| List.concat
            [ if List.length model.sites == 0 then
                [ div [] [ text "You don't have any sites yet." ]
                , button [ onClick StartCreatingSite ] [ text "Create a new site" ]
                ]
              else
                (::) (text "Your sites: ")
                <| List.reverse
                <| (::) (button [ onClick StartCreatingSite ] [ text "Create a new site" ])
                <| List.reverse
                <| List.map
                  ( \({id, domain}) ->
                    button [ onClick (EnterSite id) ]
                      [ text
                          ( if domain |> endsWith model.main_hostname then
                              domain |> dropRight (1 + String.length model.main_hostname)
                             else
                              domain
                          )
                      ]
                  )
                <| model.sites
            , [ hr [] []
              , p []
                [ text "Logged in as "
                , em [] [ text username ]
                , text ". "
                , a [ onClick Logout ] [ text "Logout" ]
                , text "."
                ]
              ]
            ]
          , Html.map SiteAction
            ( div [ id "site" ]
              [ case model.site of
                Nothing -> text ""
                Just site -> viewSite site model.main_hostname
              ]
            )
          , Html.map SiteAction
            ( div [ id "source" ]
              [ case (model.site, model.source) of
                  (Just site, Just source) -> viewSource source
                    |> Html.map (SourceAction site.id source.id)
                  _ -> text ""
              ]
            )
          ]
    , div [ id "log" ] <| List.map (div [] << (List.singleton << text)) model.log
    ]


main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

type alias Flags =
  { token : Maybe String
  , ws : String
  , main_hostname : String
  }

init : Flags -> (Model, Cmd Msg)
init {token, ws, main_hostname} =
  ( { log =
        case token of
          Just t -> [ "Logging in with token " ++ t ]
          Nothing -> []
    , user = Nothing
    , sites = []
    , site = Nothing
    , source = Nothing
    , ws = ws
    , token = token
    , main_hostname = main_hostname
    , login_with = ""
    }
  , Task.succeed Init |> Task.perform identity
  )
