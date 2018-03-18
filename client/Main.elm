import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue)
import Platform.Sub as Sub
import String exposing (split, join, trim, toInt, isEmpty, left, right)
import List exposing (head, drop, singleton, filter)
import Array exposing (Array, push, get, set)
import Array.Extra
import Result
import Json.Decode exposing
  ( decodeString, field, map3, map4
  , array, string, int
  )
import Maybe exposing (withDefault)
import Maybe.Extra exposing ((?))
import WebSocket exposing (listen, send)

import Ports exposing (..)


type alias Model =
  { log : Array Message
  , user : Maybe String
  , site : Maybe Site
  , token : Maybe String
  , ws : String
  }

type alias SiteInfo =
  { id : Int
  , subdomain : String
  }

type alias Site =
  { id : Int
  , subdomain : String
  , sources : Array Source
  }

siteDecoder = map3 Site
  (field "id" int)
  (field "subdomain" string)
  (field "sources" (array sourceDecoder))

type alias Source =
  { id : Int
  , provider : String
  , reference : String
  , root : String
  }

sourceDecoder = map4 Source
  (field "id" int)
  (field "provider" string)
  (field "reference" string)
  (field "root" string)

type Message
  = ChooseLoginMessage
  | LoginMessage String
  | SitesMessage (List SiteInfo)
  | EnterSiteMessage Int
  | SiteMessage Site
  | CreateSiteMessage String
  | PublishMessage String
  | NoticeMessage Notice
  | NotLoggedMessage
  | UnknownMessage String

type Notice
  = ErrorNotice String
  | LoginSuccessNotice String
  | CreateSiteSuccessNotice Int
  | PublishSuccessNotice String

parseMessage : String -> Message
parseMessage m =
  let
    spl = split " " m
    kind = head spl
    data = spl
      |> drop 1
      |> join " "
    params = data
      |> split ","
      |> List.map trim
      |> filter (not << isEmpty)
    first_param = params |> head |> withDefault ""
  in
    case kind of
      Just "login" ->
        LoginMessage first_param
      Just "sites" ->
        params
          |> List.map (split "=")
          |> List.map
            ( \kv ->
              let
                id = kv
                  |> head
                  |> Maybe.andThen (toInt >> Result.toMaybe)
                  |> withDefault 0
                subdomain = kv |> drop 1 |> head |> withDefault ""
              in
                SiteInfo id subdomain
            )
          |> SitesMessage
      Just "site" ->
        case decodeString siteDecoder data of
          Ok site -> SiteMessage site
          Err err -> NoticeMessage (ErrorNotice err)
      Just "notice" ->
        case first_param |> split "=" |> head of
          Just "error" ->
            first_param |> split "=" |> drop 1 |> head |> withDefault ""
              |> ErrorNotice
              |> NoticeMessage
          Just "login-success" ->
            first_param |> split "=" |> drop 1 |> head |> withDefault ""
              |> LoginSuccessNotice
              |> NoticeMessage
          Just "create-site-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> Maybe.andThen (toInt >> Result.toMaybe)
              |> withDefault 0
              |> CreateSiteSuccessNotice
              |> NoticeMessage
          Just "publish-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> withDefault ""
              |> PublishSuccessNotice
              |> NoticeMessage
          _ -> UnknownMessage m
      Just "not-logged" -> NotLoggedMessage
      _ -> UnknownMessage m

type Msg
  = NewMessage String
  | LoginUsing String
  | LoginWith String
  | EnterSite Int
  | StartCreatingSite
  | EditCreatingSite Int String
  | FinishCreatingSite Int
  | AddSource Int
  | SourceAction Int Int Int Int SourceMsg
  | Publish Int String

type SourceMsg
  = EditRoot String
  | EditProvider String
  | EditReference String
  | SaveSourceEdits
  | RemoveSource

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    LoginWith account ->
      ( model, Cmd.none )
    LoginUsing provider -> 
      ( model
      , external <| "https://accountd.xyz/login/using/" ++ provider
      )
    NewMessage m ->
      let
        nmessages = Array.length model.log
        lastmessage = model.log |> get (nmessages - 1)
        nextmessage = Debug.log "got message" <| parseMessage m
        justappendmessage = { model | log = model.log |> push nextmessage }

        nextmodel =
          if Just nextmessage == lastmessage then
            model
          else case nextmessage of
            -- if we should be logged already in there's no need to log this again
            NoticeMessage (LoginSuccessNotice user) ->
              if model.user == Just user then model
              else { justappendmessage | user = Just user }

            -- in the beggining of a session we shouldn't be logged anyway
            NotLoggedMessage -> if nmessages > 2 then justappendmessage else model

            -- if we're editing a site and get an update for that, just replace the last
            SiteMessage site -> case lastmessage of
              Just (SiteMessage lastsite) ->
                if lastsite.id == site.id then
                  { model | log = model.log |> set (nmessages - 1) nextmessage }
                else justappendmessage
              _ -> justappendmessage
            _ -> justappendmessage

        effect = case nextmessage of
          NoticeMessage (CreateSiteSuccessNotice id) ->
            Cmd.batch
              [ send model.ws "list-sites"
              , send model.ws ("enter-site " ++ toString id)
              ]
          NoticeMessage (LoginSuccessNotice user) ->
            -- if we should be logged already in there's no need to call list-sites again
            if model.user == Just user then Cmd.none
            else send model.ws "list-sites"
          NotLoggedMessage ->
            case model.token of
              Just t -> send model.ws ("login " ++ t)
              Nothing -> Cmd.none
          _ -> Cmd.none
      in
        ( nextmodel, effect )
    EnterSite id ->
      ( { model | log = model.log |> push (EnterSiteMessage id) }
      , send model.ws ("enter-site " ++ toString id)
      )
    StartCreatingSite ->
      ( { model | log = model.log |> push (CreateSiteMessage "") }
      , Cmd.none
      )
    EditCreatingSite i v -> 
      ( { model
          | log = model.log
            |> Array.Extra.update
              i
              ( \el -> case el of
                CreateSiteMessage _ -> CreateSiteMessage v
                _ -> el
              )
        }
      , Cmd.none
      )
    FinishCreatingSite i ->
      case model.log |> get i of
        Just (CreateSiteMessage subdomain) ->
          ( model
          , send model.ws ("create-site " ++ subdomain)
          )
        _ -> ( model, Cmd.none )
    AddSource siteId ->
      ( model
      , send model.ws ("add-source " ++ toString siteId)
      )
    SourceAction siteId sourceId siteMessageIdx sourceIdx sourcemsg ->
      case model.log |> get siteMessageIdx of
        Just (SiteMessage site) ->
          let
            ( nextsite, effect ) = case site.sources |> get sourceIdx of
              Just source ->
                let
                  nextsource = case sourcemsg of
                    EditRoot root -> { source | root = root }
                    EditProvider provider -> { source | provider = provider }
                    EditReference ref -> { source | reference = ref }
                    _ -> source
                  effect = case sourcemsg of
                    SaveSourceEdits ->
                      let
                        json = "{\"root\":\"" ++ source.root ++ "\",\"provider\":\""
                               ++ source.provider ++ "\", \"reference\":\""
                               ++ source.reference ++ "\"}"
                        m = ("update-source " ++ toString sourceId ++ " " ++ json)
                      in send model.ws m
                    RemoveSource ->
                      send model.ws ("remove-source " ++ toString sourceId)
                    _ -> Cmd.none
                in
                  ( { site | sources = site.sources |> set sourceIdx nextsource }
                  , effect
                  )
              Nothing -> ( site, Cmd.none )
          in
            ( { model | log = model.log |> set siteMessageIdx (SiteMessage nextsite) }
            , effect
            )
        _ -> ( model, Cmd.none )
    Publish siteId subdomain ->
      ( { model | log = model.log |> push (PublishMessage subdomain) }
      , send model.ws ("publish " ++ toString siteId)
      )
      


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ listen model.ws NewMessage
    ]

view : Model -> Html Msg
view model =
  div []
    [ ul [ class "log" ]
      <| List.indexedMap (viewMessage model)
      <| Array.toList model.log
    ]

viewMessage : Model -> Int -> Message -> Html Msg
viewMessage model i message =
  case message of
    ChooseLoginMessage ->
      li [ class "choose-login" ]
        [ text "login using "
        , button [ onClick (LoginUsing "twitter") ] [ text "twitter" ]
        , text ", "
        , button [ onClick (LoginUsing "github") ] [ text "github" ]
        , text " or "
        , button [ onClick (LoginUsing "trello") ] [ text "trello" ]
        ]
    LoginMessage token ->
      li [ class "login" ]
        [ text "Trying to log in with "
        , a [ target "_blank", href "https://accountd.xyz/" ] [ text "accountd.xyz" ]
        , text " token "
        , em [] [ text <| left 4 token ++ "..." ++ right 3 token ]
        , text "."
        ]
    SitesMessage sites ->
      li [ class "sites" ]
        [ if List.length sites == 0 then
            text "You don't have any sites yet. "
          else ul []
            <| (::) (text "Your sites: ")
            <| List.map
              ( \site ->
                button [ onClick (EnterSite site.id) ] [ text site.subdomain ]
              )
            <| sites
        , button [ onClick StartCreatingSite ] [ text "Create a new site" ]
        ]
    EnterSiteMessage id ->
      li [ class "enter-site" ]
        [ text "entering site "
        , em [] [ text <| toString id ]
        ]
    SiteMessage {id, subdomain, sources} ->
      li [ class "site" ]
        [ div []
          [ h1 []
            [ a [ href <| "http://" ++ subdomain ++ ".sitios.xyz/", target "_blank"]
              [ text subdomain ]
            , button [ onClick (Publish id subdomain) ] [ text "Publish site" ]
            ]
          , table []
            <| List.indexedMap
              ( \sidx source ->
                let vhtml = viewSource source
                in Html.map (SourceAction id source.id i sidx) vhtml
              )
            <| Array.toList sources
          , button [ onClick (AddSource id) ] [ text "Add a new data source" ]
          ]
        ]
    CreateSiteMessage subdomain ->
      li [ class "create-site" ]
        [ text "Creating site. "
        , Html.form [ onSubmit (FinishCreatingSite i) ]
          [ label []
            [ text "Please enter a subdomain:"
            , input [ onInput (EditCreatingSite i), value subdomain ] []
            ]
          , button [] [ text "Create" ]
          ]
        ]
    PublishMessage subdomain ->
      li [ class "publish" ]
        [ text "Publishing site to "
        , a [ href <| "http://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
          [ text <| "http://" ++ subdomain ++ ".sitios.xyz/"
          ]
        , text "."
        ]
    NoticeMessage not ->
      case not of
        ErrorNotice err -> li [ class "notice error" ] [ text err ] 
        LoginSuccessNotice user -> li [ class "notice login-success" ]
          [ text "Logged in successfully as "
          , em [] [ text user ]
          , text "."
          ] 
        CreateSiteSuccessNotice id -> li [ class "notice create-site-success" ]
          [ text "Created site successfully with id "
          , em [] [ text <| toString id ]
          , text "."
          ]
        PublishSuccessNotice subdomain -> li [ class "notice publish-success" ]
          [ text "Publish successfully to "
          , a [ href <| "http://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
            [ text <| "http://" ++ subdomain ++ ".sitios.xyz/"
            ]
          , text "."
          ]
    NotLoggedMessage -> case model.token of
      Just _ -> text "" -- no need to show the login buttons, we already have a token
      Nothing -> viewMessage model i ChooseLoginMessage
    UnknownMessage m -> li [ class "unknown" ] [ text m ]

viewSource : Source -> Html SourceMsg
viewSource {id, provider, reference, root} =
  tr []
    [ td []
      [ input [ value root, onInput EditRoot ] []
      ]
    , td []
      [ select [ value provider, on "change" (Json.Decode.map EditProvider targetValue) ]
        [ option [] [ text "url:html" ]
        , option [] [ text "url:markdown" ]
        ]
      ]
    , td []
      [ input [ value reference, onInput EditReference ] []
      ]
    , td []
      [ button [ onClick SaveSourceEdits ] [ text "Save" ]
      ]
    , td []
      [ button [ onClick RemoveSource ] [ text "Delete" ]
      ]
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
  }

init : Flags -> (Model, Cmd Msg)
init {token, ws} =
  ( { log =
        case token of
          Just t -> Array.fromList [ LoginMessage t ]
          Nothing -> Array.fromList [ ChooseLoginMessage ]
    , user = Nothing
    , site = Nothing
    , ws = ws
    , token = token
    }
  , Cmd.batch
    [ case token of
      Just t -> send ws ("login " ++ t)
      Nothing -> Cmd.none
    ]
  )
