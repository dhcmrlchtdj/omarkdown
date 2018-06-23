open Batteries

let trim_bom (input: string) : string =
    if String.starts_with input "\239\187\191"
    then String.tail input 3
    else input

let replace_crlf (input: string) : string =
    String.nreplace ~str:input ~sub:"\r\n" ~by:"\n"

let expand_tab (input: string) : string =
    if String.exists input "\t"
    then
        let f (p, acc) curr =
            if curr = '\t'
            then
                let n = 4 - (p mod 4) in
                (p + n, List.make n ' ' @ acc)
            else (p + 1, curr :: acc)
        in
        input
        |> String.to_list
        |> List.fold_left f (0, [])
        |> snd
        |> String.of_list
    else input

let parse (input: string) : Types.md_ast =
    UTF8.validate input ;
    input
    |> trim_bom
    |> replace_crlf
    |> String.split_on_char '\n'
    |> List.map expand_tab
    |> ParseBlock.parse
