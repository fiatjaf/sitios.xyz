module Log exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import String exposing (split, join, trim, toInt, isEmpty, left, right)
import List exposing (head, drop, singleton, filter, intersperse)
import Maybe exposing (withDefault)
import Json.Decode as D

import Site exposing (..)

type Message
  = LoginMessage String
  | SitesMessage (List (Int, String))
  | EnterSiteMessage Int
  | SiteMessage Site
  | InitCreateSiteMessage
  | EndCreateSiteMessage String
  | SaveSiteDataMessage
  | PublishMessage Int
  | DeleteMessage String
  | EnterSourceMessage Int String
  | AddingNewSourceMessage Int
  | LeaveSourceMessage Int
  | SaveSourceMessage Int String
  | RemoveSourceMessage Int String
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
                (id, subdomain)
            )
          |> SitesMessage
      Just "site" ->
        case D.decodeString siteDecoder data of
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


viewMessage : Message -> Html msg
viewMessage message =
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
          <| List.map (\(_, subdomain) -> em [] [ text subdomain ])
          <| sites
        ]
    EnterSiteMessage id ->
      div []
        [ text "Entering site "
        , em [] [ text <| toString id ]
        , text "."
        ]
    SiteMessage {id, subdomain, sources} ->
      div []
        [ text "Got site "
        , em [] [ text <| toString id ]
        , text ", "
        , em [] [ text <| "https://" ++ subdomain ++ ".sitios.xyz/" ]
        , text <| ", with " ++ (toString <| List.length sources) ++ " sources."
        ]
    InitCreateSiteMessage ->
      div [] [ text "Waiting for a subdomain to identify the new site..." ]
    EndCreateSiteMessage subdomain ->
      div []
        [ text "Creating site with subdomain"
        , em [] [ text subdomain ]
        , text "."
        ]
    SaveSiteDataMessage ->
      div [] [ text "Saving site data..." ]
    EnterSourceMessage id root ->
      div []
        [ text "Entering source "
        , em [] [ text <| toString id ]
        , text " rooted on "
        , em [] [ text root ]
        , text "."
        ]
    AddingNewSourceMessage siteId ->
      div []
        [ text "Adding new source on site "
        , em [] [ text <| toString siteId ]
        , text "."
        ]
    LeaveSourceMessage id ->
      div []
        [ text "Leaving source "
        , em [] [ text <| toString id ]
        , text "."
        ]
    SaveSourceMessage id root ->
      div []
        [ text "Saving edits made to source "
        , em [] [ text <| toString id ]
        , text " on "
        , em [] [ text root ]
        , text "."
        ]
    RemoveSourceMessage id root ->
      div []
        [ text "Removing source "
        , em [] [ text <| toString id ]
        , text " from "
        , em [] [ text root ]
        , text "."
        ]
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
    NotLoggedMessage ->
      div [] [ text "You were disconnected." ]
    UnknownMessage m ->
      div [ class "unknown" ] [ text m ]
