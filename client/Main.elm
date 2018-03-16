import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Platform.Sub as Sub
import String exposing (split, join, trim)
import List exposing (head, drop, singleton)
import Maybe exposing (withDefault)
import WebSocket exposing (listen, send)

import Ports exposing (..)


type alias Model =
  { log : List Message
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
  | NoticeMessage Notice
  | UnknownMessage String

type Notice
  = ErrorNotice String
  | LoginSuccessNotice String

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
    first_param = params |> head |> withDefault ""
  in
    case kind of
      Just "login" ->
        LoginMessage first_param
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
         _ -> UnknownMessage m
      _ ->
        UnknownMessage m

type Msg
  = NewMessage String
  | LoginUsing String
  | LoginWith String

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NewMessage m ->
      ( { model | log = (parseMessage m) :: model.log }
      , Cmd.none
      )
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
      <| List.reverse model.log
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
    NoticeMessage not ->
      case not of
        ErrorNotice err -> div [ class "notice error" ] [ text err ] 
        LoginSuccessNotice user -> div [ class "notice login-success" ]
          [ text "Logged in successfully as "
          , em [] [ text user ]
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
          Just t -> [ LoginMessage t ]
          Nothing -> [ ChooseLoginMessage ]
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
