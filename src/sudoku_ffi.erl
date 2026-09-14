%% Small Erlang shim for the bits of terminal and randomness handling that
%% Gleam's standard library does not cover.
-module(sudoku_ffi).

-export([enable_raw/0, read_byte/0, now_ms/0, shuffle/1]).
-export([file_path/1, write_file/2, read_file/1, forget_file/1]).
-export([arguments/0, columns/0, rows/0]).
-export([plain/0, set_plain/1]).

%% Put the terminal into raw mode: one byte at a time, no echo, no line
%% editing. Requires OTP 26 or later; returns false when unavailable (for
%% example when stdin is a pipe rather than a terminal).
enable_raw() ->
    try shell:start_interactive({noshell, raw}) of
        ok -> true;
        {error, already_started} -> true;
        _ -> false
    catch
        _:_ -> false
    end.

%% Read a single byte, or -1 on end of input.
read_byte() ->
    case io:get_chars(standard_io, "", 1) of
        eof -> -1;
        {error, _} -> -1;
        [C] -> C;
        <<C>> -> C;
        _ -> -1
    end.

now_ms() ->
    erlang:monotonic_time(millisecond).

shuffle(List) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), E} || E <- List])].

%% Where the game keeps what it remembers: under XDG_DATA_HOME if the
%% environment names one, and under ~/.local/share otherwise.
file_path(Name) ->
    unicode:characters_to_binary(kept(Name)).

kept(Name) ->
    Base = case os:getenv("XDG_DATA_HOME") of
               Dir when is_list(Dir), Dir =/= "" -> Dir;
               _ -> filename:join(home(), ".local/share")
           end,
    filename:join([Base, "sudoku", binary_to_list(Name)]).

home() ->
    case os:getenv("HOME") of
        Dir when is_list(Dir), Dir =/= "" -> Dir;
        _ -> "."
    end.

write_file(Name, Text) ->
    Path = kept(Name),
    case filelib:ensure_dir(Path) of
        ok -> file:write_file(Path, Text) =:= ok;
        _ -> false
    end.

read_file(Name) ->
    case file:read_file(kept(Name)) of
        {ok, Text} -> {ok, Text};
        _ -> {error, nil}
    end.

forget_file(Name) ->
    _ = file:delete(kept(Name)),
    nil.

%% What was asked for on the command line, after the `--`.
arguments() ->
    [unicode:characters_to_binary(Argument)
     || Argument <- init:get_plain_arguments()].

%% Whether to draw without colour. NO_COLOR is the usual way of asking for
%% that across command line tools, so it is the one this honours; --plain sets
%% the same switch. Looked up once and kept, since it is asked hundreds of
%% times a frame.
plain() ->
    case persistent_term:get(sudoku_plain, undefined) of
        undefined ->
            Plain = case os:getenv("NO_COLOR") of
                        Value when is_list(Value), Value =/= "" -> true;
                        _ -> false
                    end,
            persistent_term:put(sudoku_plain, Plain),
            Plain;
        Plain ->
            Plain
    end.

set_plain(Plain) ->
    persistent_term:put(sudoku_plain, Plain),
    nil.

%% How much room the terminal has, or -1 where it will not say.
columns() -> measure(fun io:columns/0).

rows() -> measure(fun io:rows/0).

measure(Ask) ->
    case Ask() of
        {ok, Count} -> Count;
        _ -> -1
    end.
