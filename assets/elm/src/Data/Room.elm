module Data.Room
    exposing
        ( RoomSubscriptionConnection
        , RoomSubscriptionEdge
        , RoomSubscription
        , Room
        , roomSubscriptionConnectionDecoder
        , roomDecoder
        , slugParser
        )

import Json.Decode as Decode
import Json.Decode.Pipeline as Pipeline
import UrlParser


-- TYPES


type alias RoomSubscriptionConnection =
    { edges : List RoomSubscriptionEdge
    }


type alias RoomSubscriptionEdge =
    { node : RoomSubscription
    }


type alias RoomSubscription =
    { room : Room
    }


type alias Room =
    { id : String
    , name : String
    , description : String
    }



-- DECODERS


roomSubscriptionConnectionDecoder : Decode.Decoder RoomSubscriptionConnection
roomSubscriptionConnectionDecoder =
    Pipeline.decode RoomSubscriptionConnection
        |> Pipeline.custom (Decode.at [ "edges" ] (Decode.list roomSubscriptionEdgeDecoder))


roomSubscriptionEdgeDecoder : Decode.Decoder RoomSubscriptionEdge
roomSubscriptionEdgeDecoder =
    Pipeline.decode RoomSubscriptionEdge
        |> Pipeline.custom (Decode.at [ "node" ] roomSubscriptionDecoder)


roomSubscriptionDecoder : Decode.Decoder RoomSubscription
roomSubscriptionDecoder =
    Pipeline.decode RoomSubscription
        |> Pipeline.custom (Decode.at [ "room" ] roomDecoder)


roomDecoder : Decode.Decoder Room
roomDecoder =
    Pipeline.decode Room
        |> Pipeline.required "id" Decode.string
        |> Pipeline.required "name" Decode.string
        |> Pipeline.required "description" Decode.string



-- ROUTING


slugParser : UrlParser.Parser (String -> a) a
slugParser =
    UrlParser.string