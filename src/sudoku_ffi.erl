%% Small Erlang shim for the bits of terminal and randomness handling that
%% Gleam's standard library does not cover.
-module(sudoku_ffi).

-export([enable_raw/0, read_byte/0, now_ms/0, shuffle/1]).

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
