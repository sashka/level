module Data.Space exposing (Space, fragment, decoder)

import Json.Decode as Decode exposing (Decoder, field, maybe, string)
import GraphQL exposing (Fragment)


-- TYPES


type alias Space =
    { id : String
    , name : String
    , slug : String
    , avatarUrl : Maybe String
    }


fragment : Fragment
fragment =
    GraphQL.fragment
        """
        fragment SpaceFields on Space {
          id
          name
          slug
          avatarUrl
        }
        """
        []



-- DECODERS


decoder : Decoder Space
decoder =
    Decode.map4 Space
        (field "id" string)
        (field "name" string)
        (field "slug" string)
        (field "avatarUrl" (maybe string))
