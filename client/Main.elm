import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Platform.Sub as Sub
import String exposing (split, join, trim, toInt, isEmpty)
import List exposing (head, drop, singleton, filter)
import Array exposing (Array, push, get, set)
import Array.Extra
import Result
import Maybe exposing (withDefault)
import Maybe.Extra exposing ((?))
import WebSocket exposing (listen, send)

import Ports exposing (..)


type alias Model =
  { log : Array Message
  , user : Maybe String
  , site : Maybe Site
  , ws : String
  }

type alias Site =
  { id : Int
  , subdomain : String
  }

type Message
  = ChooseLoginMessage
  | LoginMessage String
  | SitesMessage (List Site)
  | CreateSiteMessage String
  | EnterSiteMessage Int
  | NoticeMessage Notice
  | UnknownMessage String

type Notice
  = ErrorNotice String
  | LoginSuccessNotice String
  | CreateSiteSuccessNotice Int

parseMessage : String -> Message
parseMessage m =
  let
    spl = split " " m
    kind = head spl
    params = spl
      |> drop 1
      |> join " "
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
                Site id subdomain
            )
          |> SitesMessage
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
          _ -> UnknownMessage m
      _ ->
        UnknownMessage m

type Msg
  = NewMessage String
  | EnterSite Int
  | StartCreatingSite
  | EditCreatingSite Int String
  | FinishCreatingSite Int
  | LoginUsing String
  | LoginWith String

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NewMessage m ->
      let
        nmessages = Array.length model.log
        lastmessage = model.log
          |> get (nmessages - 1)
        nextmessage = parseMessage m
      in
        ( { model
            | log =
                if Just nextmessage == lastmessage then
                  model.log
                else
                  model.log |> push nextmessage
          }
        , case nextmessage of
          NoticeMessage (CreateSiteSuccessNotice id) ->
            send model.ws ("enter-site " ++ toString id)
          _ -> Cmd.none
        )
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
    LoginWith account ->
      ( model, Cmd.none )
    LoginUsing provider -> 
      ( model
      , external <| "https://accountd.xyz/login/using/" ++ provider
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
      <| List.map (li [] << singleton)
      <| List.indexedMap (viewMessage model)
      <| Array.toList model.log
    ]

viewMessage : Model -> Int -> Message -> Html Msg
viewMessage model i message =
  case message of
    ChooseLoginMessage ->
      div [ class "choose-login" ]
        [ text "login using "
        , button [ onClick (LoginUsing "twitter") ] [ text "twitter" ]
        , text ", "
        , button [ onClick (LoginUsing "github") ] [ text "github" ]
        , text " or "
        , button [ onClick (LoginUsing "trello") ] [ text "trello" ]
        ]
    LoginMessage token ->
      div [ class "login" ]
        [ text "Trying to log in with "
        , a [ target "_blank", href "https://accountd.xyz/" ] [ text "accountd.xyz" ]
        , text " token "
        , em [] [ text token ]
        , text "."
        ]
    SitesMessage sites ->
      div [ class "sites" ]
        [ if List.length sites == 0 then text ""
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
      div [ class "enter-site" ]
        [ text "entering site "
        , em [] [ text <| toString id ]
        ]
    CreateSiteMessage subdomain ->
      div [ class "create-site" ]
        [ text "Creating site. "
        , Html.form [ onSubmit (FinishCreatingSite i) ]
          [ label []
            [ text "Please enter a subdomain:"
            , input [ onInput (EditCreatingSite i), value subdomain ] []
            ]
          , button [] [ text "Create" ]
          ]
        ]
    NoticeMessage not ->
      case not of
        ErrorNotice err -> div [ class "notice error" ] [ text err ] 
        LoginSuccessNotice user -> div [ class "notice login-success" ]
          [ text "Logged in successfully as "
          , em [] [ text user ]
          , text "."
          ] 
        CreateSiteSuccessNotice id -> div [ class "notice create-site-success" ]
          [ text "Created site successfully with id "
          , em [] [ text <| toString id ]
          , text "."
          ]
    UnknownMessage m -> div [ class "unknown" ] [ text m ]


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
    }
  , Cmd.batch
    [ case token of
      Just t -> send ws ("login " ++ t)
      Nothing -> Cmd.none
    ]
  )
