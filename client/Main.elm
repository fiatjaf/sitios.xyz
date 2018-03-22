import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, on, targetValue)
import Platform.Sub as Sub
import List exposing (head, drop, singleton, filter, intersperse)
import Array exposing (set, get, append, slice, push)
import WebSocket exposing (listen, send)
import Json.Encode as E

import Ports exposing (..)
import Log exposing (..)
import Site exposing (..)

type alias Model =
  { log : List Message
  , user : Maybe String
  , sites : List (Int, String)
  , site : Maybe Site
  , source : Maybe Source
  , token : Maybe String
  , ws : String
  }

type Msg
  = NewMessage String
  | LoginUsing String
  | LoginWith String
  | EnterSite Int
  | StartCreatingSite
  | SiteAction Site.Msg

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
            Cmd.batch
              [ send model.ws ("enter-site " ++ toString id)
              , send model.ws "list-sites"
              ]
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
      ( { model
          | log = model.log |> (::) (CreateSiteMessage "")
          , site = Just emptySite
        }
      , Cmd.none
      )
    SiteAction msg -> case model.site of
      Nothing -> ( model, Cmd.none )
      Just site -> case msg of
        EditSubdomain subdomain -> 
          ( { model | site = Just { site | subdomain = subdomain } }
          , Cmd.none
          )
        FinishCreatingSite -> 
          if site.id == 0 then
            ( { model | site = Nothing }
            , send model.ws ("create-site " ++ site.subdomain)
            )
          else ( model , Cmd.none )
        SiteDataAction sdmsg ->
          let
            data = site.data
            newdata = case sdmsg of
              EditName v -> { data | name = v }
              EditDescription v -> { data | description = v }
              EditFavicon v -> { data | favicon = v }
              EditAside v -> { data | aside = v }
              EditFooter v -> { data | footer = v }
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
            ( { model | site = Just newsite }
            , case sdmsg of
              SaveSiteData ->
                let
                  id = toString site.id
                  data = E.encode 0 <| siteDataEncoder site.data
                in send model.ws ("update-site-data " ++ id ++ " " ++ data)
              _ -> Cmd.none
            )
        Publish ->
          ( { model | log = model.log |> (::) (PublishMessage site.id) }
          , send model.ws ("publish " ++ toString site.id)
          )
        Delete ->
          ( { model | log = model.log |> (::) (DeleteMessage site.subdomain) }
          , send model.ws ("delete-site " ++ toString site.id)
          )
        EnterSource source ->
          ( { model | source = Just source }
          , Cmd.none
          )
        AddSource ->
          ( model 
          , send model.ws ("add-source " ++ toString site.id)
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
                ( \(id, subdomain) ->
                  button [ onClick (EnterSite id) ] [ text subdomain ]
                )
              <| model.sites
          , Html.map SiteAction
            ( div [ id "site" ]
              [ case model.site of
                Nothing -> text ""
                Just site -> viewSite site
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
    , div [ id "log" ] <| List.map viewMessage model.log
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
          Just t -> [ LoginMessage t ]
          Nothing -> []
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
