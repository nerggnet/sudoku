%% Small Erlang shim for the bits of terminal and randomness handling that
%% Gleam's standard library does not cover.
-module(sudoku_ffi).

-export([enable_raw/0, read_byte/0, now_ms/0, shuffle/1]).
-export([save_path/0, write_save/1, read_save/0, forget_save/0]).
-export([arguments/0, columns/0, rows/0]).

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

%% Where a game in progress is kept: under XDG_DATA_HOME if the environment
%% names one, and under ~/.local/share otherwise.
save_path() ->
    unicode:characters_to_binary(save_file()).

save_file() ->
    Base = case os:getenv("XDG_DATA_HOME") of
               Dir when is_list(Dir), Dir =/= "" -> Dir;
               _ -> filename:join(home(), ".local/share")
           end,
    filename:join([Base, "sudoku", "game"]).

home() ->
    case os:getenv("HOME") of
        Dir when is_list(Dir), Dir =/= "" -> Dir;
        _ -> "."
    end.

write_save(Text) ->
    Path = save_file(),
    case filelib:ensure_dir(Path) of
        ok -> file:write_file(Path, Text) =:= ok;
        _ -> false
    end.

read_save() ->
    case file:read_file(save_file()) of
        {ok, Text} -> {ok, Text};
        _ -> {error, nil}
    end.

forget_save() ->
    _ = file:delete(save_file()),
    nil.

%% What was asked for on the command line, after the `--`.
arguments() ->
    [unicode:characters_to_binary(Argument)
     || Argument <- init:get_plain_arguments()].

%% How much room the terminal has, or -1 where it will not say.
columns() -> measure(fun io:columns/0).

rows() -> measure(fun io:rows/0).

measure(Ask) ->
    case Ask() of
        {ok, Count} -> Count;
        _ -> -1
    end.
