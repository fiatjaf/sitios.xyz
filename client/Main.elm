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
  , sites : List SiteInfo
  , site : Maybe Site
  , source : Maybe Source
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
  | DeleteMessage String
  | NoticeMessage Notice
  | NotLoggedMessage
  | UnknownMessage String

type Notice
  = ErrorNotice String
  | LoginSuccessNotice String
  | CreateSiteSuccessNotice Int
  | PublishSuccessNotice String
  | DeleteSuccessNotice String

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
          Just "delete-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> withDefault ""
              |> DeleteSuccessNotice
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
  | EnterSource Source
  | AddSource Int
  | SourceAction Int Int SourceMsg
  | Publish Int String
  | Delete Int String

type SourceMsg
  = EditRoot String
  | EditProvider String
  | EditReference String
  | SaveSourceEdits
  | RemoveSource
  | LeaveSource

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
        appendmessage = { model | log = model.log |> push nextmessage }

        nextmodel =
          if Just nextmessage == lastmessage then
            model
          else case nextmessage of
            SiteMessage site -> { appendmessage | site = Just site }
            SitesMessage sites -> { appendmessage | sites = sites }
            NoticeMessage (LoginSuccessNotice user) ->
              { appendmessage | user = Just user }
            _ -> appendmessage

        effect = case nextmessage of
          NoticeMessage (CreateSiteSuccessNotice id) ->
            send model.ws ("enter-site " ++ toString id)
          NoticeMessage (LoginSuccessNotice user) ->
            send model.ws "list-sites"
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
    EnterSource source ->
      ( { model | source = Just source }
      , Cmd.none
      )
    AddSource siteId ->
      ( model
      , send model.ws ("add-source " ++ toString siteId)
      )
    SourceAction siteId sourceId sourcemsg ->
      case model.source of
        Nothing -> ( model, Cmd.none )
        Just source ->
          let
            nextsource = case sourcemsg of
              EditRoot root -> Just { source | root = root }
              EditProvider provider -> Just { source | provider = provider }
              EditReference ref -> Just { source | reference = ref }
              LeaveSource -> Nothing
              _ -> model.source
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
            ( { model | source = nextsource }
            , effect
            )
    Publish siteId subdomain ->
      ( { model | log = model.log |> push (PublishMessage subdomain) }
      , send model.ws ("publish " ++ toString siteId)
      )
    Delete siteId subdomain ->
      ( { model | log = model.log |> push (DeleteMessage subdomain) }
      , send model.ws ("delete-site " ++ toString siteId)
      )


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ listen model.ws NewMessage
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
          , text " or "
          , button [ onClick (LoginUsing "trello") ] [ text "trello" ]
          ]
      Just username ->
        div [ id "main" ]
          [ div [ id "list" ]
            [ if List.length model.sites == 0 then
                text "You don't have any sites yet. "
              else ul []
                <| (::) (text "Your sites: ")
                <| List.map
                  ( \site ->
                    button [ onClick (EnterSite site.id) ] [ text site.subdomain ]
                  )
                <| model.sites
            , button [ onClick StartCreatingSite ] [ text "Create a new site" ]
            ]
          , div [ id "site" ]
            [ case model.site of
              Nothing -> text ""
              Just {subdomain, sources, id} ->
                div []
                  [ h1 []
                    [ a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank"]
                      [ text subdomain ]
                    , button [ onClick (Publish id subdomain) ] [ text "Publish site" ]
                    , button [ onClick (Delete id subdomain) ] [ text "Delete site" ]
                    ]
                  , ul []
                    <| List.map
                      ( \source ->
                        li [ class "source" ]
                          [ a [ onClick (EnterSource source) ]
                            [ text <| source.root ++ " -> " ++ source.provider
                            ]
                          ]
                      )
                    <| Array.toList sources
                  , button [ onClick (AddSource id) ] [ text "Add a new data source" ]
                  ]
            ]
          , div [ id "source" ]
            [ case (model.site, model.source) of
                (Just site, Just source) -> viewSource source
                  |> Html.map (SourceAction site.id source.id)
                _ -> text ""
            ]
          ]
    , ul [ id "log" ]
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
            [ a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank"]
              [ text subdomain ]
            , button [ onClick (Publish id subdomain) ] [ text "Publish site" ]
            , button [ onClick (Delete id subdomain) ] [ text "Delete site" ]
            ]
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
        , a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
          [ text <| "https://" ++ subdomain ++ ".sitios.xyz/"
          ]
        , text "."
        ]
    DeleteMessage subdomain ->
      li [ class "delete" ]
        [ text "Deleting "
        , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
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
          , a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
            [ text <| "https://" ++ subdomain ++ ".sitios.xyz/"
            ]
          , text "."
          ]
        DeleteSuccessNotice subdomain -> li [ class "notice delete-success" ]
          [ text "Deleted "
          , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
          , text "."
          ]
    NotLoggedMessage -> case model.token of
      Just _ -> li [ class "not-logged" ] [ text "you were disconnected." ]
      Nothing -> viewMessage model i ChooseLoginMessage
    UnknownMessage m -> li [ class "unknown" ] [ text m ]

viewSource : Source -> Html SourceMsg
viewSource {id, provider, reference, root} =
  div []
    [ button [ onClick LeaveSource ] [ text "close" ]
    , label []
      [ text "Root:"
      , input [ value root, onInput EditRoot ] []
      ]
    , label []
      [ text "Provider:"
      , select [ value provider, on "change" (Json.Decode.map EditProvider targetValue) ]
        [ option [] [ text "" ]
        , option [] [ text "url:html" ]
        , option [] [ text "url:markdown" ]
        , option [] [ text "trello:list" ]
        ]
      ]
    , label []
      [ text "Reference:"
      , input [ value reference, onInput EditReference ] []
      ]
    , div []
      [ button [ onClick SaveSourceEdits ] [ text "Save" ]
      ]
    , div []
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
    , sites = []
    , site = Nothing
    , source = Nothing
    , ws = ws
    , token = token
    }
  , Cmd.batch
    [ case token of
      Just t -> send ws ("login " ++ t)
      Nothing -> Cmd.none
    ]
  )
