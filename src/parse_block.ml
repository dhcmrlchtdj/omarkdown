open Batteries
open R.Infix

type block =
    | AtxHeader of UTF8.t
    | SetexHeader of UTF8.t * UTF8.t
    | CodeBlock of UTF8.t list
    | BlockQuote of UTF8.t list
    | HorizontalRule
    | UnorderedList of UTF8.t list
    | OrderedList of UTF8.t list
    | Paragraph of UTF8.t list
    | ReferenceResolutionBlock of UTF8.t list
    | NullBlock

let re_ref =
    R.compile
        "^ *\\[((((\\\\\\[)|(\\\\\\])|[^]])+)|(!\\[((\\\\\\[)|(\\\\\\])|[^]])+\\])|(!\\[((\\\\\\[)|(\\\\\\])|[^]])+\\]\\[((\\\\\\[)|(\\\\\\])|[^]])+\\]))\\] *: *([^ <>]+|<[^<>]*>)( .*)?$"


let re_ref_end =
    R.compile
        "^ +((\"([^\"\\\\]|\\\\.)*\")|('([^'\\\\]|\\\\.)*')|(\\(([^(\\\\]|\\\\.)*\\))) *$"


let re_horizontal =
    R.compile
        "^ *((\\* *\\* *\\* *[\\* ]*)|(\\- *\\- *\\- *[\\- ]*)|(_ *_ *_ *[_ ]*))$"


let re_unorder = R.compile "^( *[-+*] +)[^ ]"

let re_order = R.compile "^( *[0-9]+\\. +)[^ ]"

let re_header = R.compile "^(-+|=+) *$"

let begin_with_four_space = String.starts_with "    "

let first_non_space (s: string) : char option =
    s |> String.enum |> Enum.drop_while (fun x -> x = ' ') |> Enum.get


let include_non_space (len: int) (s: string) : bool =
    s |> String.enum |> Enum.take len
    |> Enum.exists (function ' ' -> false | _ -> true)


let space_only (s: string) : bool =
    s |> String.enum |> Enum.for_all (function ' ' -> true | _ -> false)


let rec advance_code_block (acc: UTF8.t list) = function
    | [] -> (acc, [])
    | a :: (b :: _ as t) when b <> "" && not (begin_with_four_space b) ->
        (a :: acc, t)
    | a :: ("" :: b :: _ as t) when not (begin_with_four_space b) -> (a :: acc, t)
    | h :: t -> advance_code_block (h :: acc) t


let rec advance_quote_block (acc: UTF8.t list) = function
    | [] -> (acc, [])
    | "" :: ("" :: _ as t) -> ("" :: acc, t)
    | "" :: (a :: _ as t) when begin_with_four_space a -> ("" :: acc, t)
    | "" :: (a :: _ as t) when first_non_space a <> Some '>' -> ("" :: acc, t)
    | a :: b :: c
        when a <> "" && not (begin_with_four_space b) && re_horizontal =~ b ->
        (a :: acc, b :: c)
    | h :: t -> advance_quote_block (h :: acc) t


let rec advance_unordered_list (starter: string) (starter_len: int)
        (acc: UTF8.t list) = function
    | [] -> (acc, [])
    | "" :: ("" :: _ as t) -> ("" :: acc, t)
    | "" :: (a :: _ as t)
        when not (String.starts_with a starter) && include_non_space starter_len a ->
        ("" :: acc, t)
    | a :: (b :: _ as t)
        when a <> "" && not (String.starts_with starter b)
             && include_non_space starter_len b && not (begin_with_four_space b)
             && (re_unorder =~ b || re_order =~ b || re_horizontal =~ b) ->
        (a :: acc, t)
    | h :: t -> advance_unordered_list starter starter_len (h :: acc) t


let rec advance_ordered_list (starter_len: int) (acc: UTF8.t list) = function
    | [] -> (acc, [])
    | "" :: ("" :: _ as t) -> ("" :: acc, t)
    | "" :: (a :: _ as t)
        when not (re_order =~ a) && include_non_space starter_len a ->
        ("" :: acc, t)
    | a :: (b :: _ as t)
        when a <> "" && not (re_order =~ b) && include_non_space starter_len b
             && not (begin_with_four_space b)
             && (re_unorder =~ b || re_horizontal =~ b) ->
        (a :: acc, t)
    | h :: t -> advance_ordered_list starter_len (h :: acc) t


let split_to_block (input: UTF8.t list) =
    let rec aux acc = function
        | [] -> List.rev acc
        | "" :: t ->
            let block = NullBlock in
            aux (block :: acc) t
        | h :: t when not (begin_with_four_space h) && re_ref =~ h -> (
                let m = R.exec re_ref h in
                match m with
                    | Some mm ->
                        let trailing_seq = mm.(18) in
                        let b, tt =
                            if space_only trailing_seq then
                                match t with
                                    | x :: (_ :: _ as y) when re_ref_end =~ x -> ([h; x], y)
                                    | _ -> ([h], t)
                            else ([h], t)
                        in
                        let block = ReferenceResolutionBlock b in
                        aux (block :: acc) tt
                    | _ -> failwith "never" )
        | h1 :: h2 :: t when re_header =~ h2 ->
            let block = SetexHeader (h1, h2) in
            aux (block :: acc) t
        | h :: t when String.starts_with "    " h ->
            let b, tt = advance_code_block [] (h :: t) in
            let block = CodeBlock (List.rev b) in
            aux (block :: acc) tt
        | h :: t when String.starts_with "#" h ->
            let block = AtxHeader h in
            aux (block :: acc) t
        | h :: t when first_non_space h = Some '>' ->
            let b, tt = advance_quote_block [] (h :: t) in
            let block = BlockQuote (List.rev b) in
            aux (block :: acc) tt
        | h :: t when re_horizontal =~ h ->
            let block = HorizontalRule in
            aux (block :: acc) t
        | h :: t when re_unorder =~ h -> (
                let m = R.exec re_unorder h in
                match m with
                    | Some [|_; starter|] ->
                        let starter_len = String.length starter in
                        let b, tt =
                            advance_unordered_list starter starter_len [] (h :: t)
                        in
                        let block = UnorderedList (List.rev b) in
                        aux (block :: acc) tt
                    | _ -> failwith "never" )
        | h :: t when re_order =~ h -> (
                let m = R.exec re_order h in
                match m with
                    | Some [|_; starter|] ->
                        let starter_len = String.length starter in
                        let b, tt = advance_ordered_list starter_len [] (h :: t) in
                        let block = OrderedList (List.rev b) in
                        aux (block :: acc) tt
                    | _ -> failwith "never" )
        | _ :: t ->
            (* TODO *)
            let block = Paragraph [] in
            aux (block :: acc) t
    in
    aux [] input

