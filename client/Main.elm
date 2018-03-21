import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue)
import Platform.Sub as Sub
import String exposing (split, join, trim, toInt, isEmpty, left, right)
import List exposing (head, drop, singleton, filter, intersperse)
import Array exposing (Array)
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
  { log : List Message
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
  = LoginMessage String
  | SitesMessage (List SiteInfo)
  | EnterSiteMessage Int
  | SiteMessage Site
  | CreateSiteMessage String
  | PublishMessage Int
  | DeleteMessage String
  | ErrorMessage String
  | LoginSuccessMessage String
  | CreateSiteSuccessMessage Int
  | PublishSuccessMessage String
  | DeleteSuccessMessage String
  | NotLoggedMessage
  | UnknownMessage String

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
          Err err -> ErrorMessage err
      Just "notice" ->
        case first_param |> split "=" |> head of
          Just "error" ->
            first_param |> split "=" |> drop 1 |> head |> withDefault ""
              |> ErrorMessage
          Just "login-success" ->
            first_param |> split "=" |> drop 1 |> head |> withDefault ""
              |> LoginSuccessMessage
          Just "create-site-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> Maybe.andThen (toInt >> Result.toMaybe)
              |> withDefault 0
              |> CreateSiteSuccessMessage
          Just "publish-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> withDefault ""
              |> PublishSuccessMessage
          Just "delete-success" ->
            first_param
              |> split "="
              |> drop 1
              |> head
              |> withDefault ""
              |> DeleteSuccessMessage
          _ -> UnknownMessage m
      Just "not-logged" -> NotLoggedMessage
      _ -> UnknownMessage m

type Msg
  = NewMessage String
  | LoginUsing String
  | LoginWith String
  | EnterSite Int
  | StartCreatingSite
  | EditCreatingSite String
  | FinishCreatingSite
  | EnterSource Source
  | AddSource Int
  | SourceAction Int Int SourceMsg
  | Publish Int
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
        lastmessage = head model.log
        nextmessage = Debug.log "got message" <| parseMessage m
        appendmessage = { model | log = model.log |> (::) nextmessage }

        nextmodel =
          if Just nextmessage == lastmessage then
            model
          else case nextmessage of
            SiteMessage site -> { appendmessage | site = Just site }
            SitesMessage sites -> { appendmessage | sites = sites }
            LoginSuccessMessage user ->
              { appendmessage | user = Just user }
            _ -> appendmessage

        effect = case nextmessage of
          CreateSiteSuccessMessage id ->
            send model.ws ("enter-site " ++ toString id)
          LoginSuccessMessage user ->
            send model.ws "list-sites"
          NotLoggedMessage ->
            case model.token of
              Just t -> send model.ws ("login " ++ t)
              Nothing -> Cmd.none
          _ -> Cmd.none
      in
        ( nextmodel, effect )
    EnterSite id ->
      ( { model | log = model.log |> (::) (EnterSiteMessage id) }
      , send model.ws ("enter-site " ++ toString id)
      )
    StartCreatingSite ->
      ( { model | log = model.log |> (::) (CreateSiteMessage "") }
      , Cmd.none
      )
    EditCreatingSite subdomain -> 
      ( { model
          | site = case model.site of
            Nothing -> Nothing
            Just site -> Just { site | subdomain = subdomain }
        }
      , Cmd.none
      )
    FinishCreatingSite ->
      case model.site of
        Just site ->
          if site.id == 0 then
            ( { model | site = Nothing }
            , send model.ws ("create-site " ++ site.subdomain)
            )
          else ( model , Cmd.none )
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
    Publish siteId ->
      ( { model | log = model.log |> (::) (PublishMessage siteId) }
      , send model.ws ("publish " ++ toString siteId)
      )
    Delete siteId subdomain ->
      ( { model | log = model.log |> (::) (DeleteMessage subdomain) }
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
          [ div [ id "list" ] <|
            if List.length model.sites == 0 then
              [ text "You don't have any sites yet. " ]
            else
              (::) (text "Your sites: ")
              <| List.reverse
              <| (::) (button [ onClick StartCreatingSite ] [ text "Create a new site" ])
              <| List.reverse
              <| List.map
                ( \site ->
                  button [ onClick (EnterSite site.id) ] [ text site.subdomain ]
                )
              <| model.sites
          , div [ id "site" ]
            [ case model.site of
              Nothing -> text ""
              Just {id, subdomain, sources} ->
                if id == 0 then -- creating site
                  Html.form [ onSubmit FinishCreatingSite ]
                    [ label []
                      [ text "Please enter a subdomain:"
                      , input [ onInput EditCreatingSite, value subdomain ] []
                      ]
                    , button [] [ text "Create" ]
                    ]
                else div [] -- already created
                  [ div []
                    [ a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
                      [ text "Visit site"
                      ]
                    ]
                  , h1 [] [ text subdomain ]
                  , div []
                    [ button [ onClick (Publish id) ] [ text "Publish site" ]
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
                  , div []
                    [ button [ onClick (Delete id subdomain) ] [ text "Delete site" ]
                    ]
                  ]
            ]
          , div [ id "source" ]
            [ case (model.site, model.source) of
                (Just site, Just source) -> viewSource source
                  |> Html.map (SourceAction site.id source.id)
                _ -> text ""
            ]
          ]
    , div [ id "log" ]
      <| List.indexedMap (viewMessage model) model.log
    ]

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
      , select [ on "change" (Json.Decode.map EditProvider targetValue) ]
        <| List.map
          ( \p ->
            option [ selected <| provider == p ] [ text p ]
          )
        <| [ ""
           , "url:html"
           , "url:markdown"
           , "trello:list"
           , "evernote:note"
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

viewMessage : Model -> Int -> Message -> Html Msg
viewMessage model i message =
  case message of
    LoginMessage token ->
      div []
        [ text "Trying to log in with "
        , a [ target "_blank", href "https://accountd.xyz/" ] [ text "accountd.xyz" ]
        , text " token "
        , em [] [ text <| left 4 token ++ "..." ++ right 3 token ]
        , text "."
        ]
    SitesMessage sites ->
      div []
        [ text "Got list of sites: "
        , span []
          <| intersperse (text ", ")
          <| List.map (\{subdomain} -> em [] [ text subdomain ])
          <| sites
        ]
    EnterSiteMessage id ->
      div []
        [ text "Entering site "
        , em [] [ text <| toString id ]
        ]
    SiteMessage {id, subdomain, sources} ->
      div []
        [ text "Entered site "
        , em [] [ text <| toString id ]
        , text ", "
        , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
        , text <| ", with " ++ (toString <| Array.length sources) ++ " sources."
        ]
    CreateSiteMessage subdomain ->
      div [] [ text "Creating site..." ]
    PublishMessage id ->
      div []
        [ text "Publishing site "
        , em [] [ text <| toString id ]
        , text "."
        ]
    DeleteMessage subdomain ->
      div []
        [ text "Deleting "
        , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
        , text "."
        ]
    ErrorMessage err -> div [ class "error" ] [ text err ] 
    LoginSuccessMessage user -> div [ class "login-success" ]
      [ text "Logged in successfully as "
      , em [] [ text user ]
      , text "."
      ] 
    CreateSiteSuccessMessage id -> div []
      [ text "Created site successfully with id "
      , em [] [ text <| toString id ]
      , text "."
      ]
    PublishSuccessMessage subdomain -> div []
      [ text "Publish successfully to "
      , a [ href <| "https://" ++ subdomain ++ ".sitios.xyz/", target "_blank" ]
        [ text <| "https://" ++ subdomain ++ ".sitios.xyz/"
        ]
      , text "."
      ]
    DeleteSuccessMessage subdomain -> div []
      [ text "Deleted "
      , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
      , text "."
      ]
    NotLoggedMessage -> case model.token of
      Just _ -> div [] [ text "You were disconnected." ]
      Nothing -> div [] [ text "Waiting for login." ]
    UnknownMessage m -> li [ class "unknown" ] [ text m ]

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
          Just t -> [ LoginMessage t ]
          Nothing -> [ NotLoggedMessage ]
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
