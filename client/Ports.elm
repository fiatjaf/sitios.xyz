port module Ports exposing (..)

port external : String -> Cmd msg
port generate_subdomain : Bool -> Cmd msg

port generated_subdomain : (String -> msg) -> Sub msg
