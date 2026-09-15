%% Small Erlang shim for the bits of terminal and randomness handling that
%% Gleam's standard library does not cover.
-module(sudoku_ffi).

-export([enable_raw/0, read_byte/0, read_byte_after/1, now_ms/0, shuffle/1]).
-export([file_path/1, write_file/2, read_file/1, forget_file/1]).
-export([arguments/0, columns/0, rows/0]).
-export([plain/0, set_plain/1]).
-export([protected/2]).

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

%% Run the game, and give the terminal back however it ends.
%%
%% Without this, anything the game falls over on leaves a terminal on the
%% alternate screen, in raw mode, with the cursor hidden — which is where
%% the report saying what went wrong would then be printed, for nobody. The
%% error goes on to be reported as it always would, on a screen that can
%% show it.
%%
%% Whatever goes wrong while giving the screen back is let go: it is almost
%% certainly the same thing that went wrong in the first place, and the
%% first thing to go wrong is the one worth reporting.
protected(Play, Restore) ->
    try
        Play()
    after
        catch Restore()
    end.

%% Read a single byte, or -1 on end of input.
read_byte() ->
    waiting(reader(), infinity).

%% The same, giving up after so many milliseconds and answering -2. That is
%% how a screen with a clock on it gets drawn again while nobody is typing.
read_byte_after(Timeout) ->
    waiting(reader(), Timeout).

%% A read that can give up needs somewhere to give up from, and
%% io:get_chars cannot be hurried. So the reading is done next door: one
%% process that does nothing but read bytes and post them here, where they
%% wait in the mailbox to be asked for. A key pressed while the screen is
%% being drawn is not lost, only not read yet.
%%
%% Every read goes through it, timed or not. Two readers on one terminal
%% would take a byte each in whatever order they happened to be waiting,
%% which is a way of typing `hjkl` and moving in three directions.
reader() ->
    case persistent_term:get(sudoku_reader, undefined) of
        Pid when is_pid(Pid) -> Pid;
        _ ->
            Game = self(),
            Pid = spawn(fun() -> reading(Game) end),
            persistent_term:put(sudoku_reader, Pid),
            Pid
    end.

reading(Game) ->
    case io:get_chars(standard_io, "", 1) of
        [C] -> Game ! {sudoku_byte, C}, reading(Game);
        <<C>> -> Game ! {sudoku_byte, C}, reading(Game);
        %% End of input, or a terminal that has stopped answering. Said
        %% once, and then the process is gone — which is itself the answer
        %% to anybody who asks again.
        _ -> Game ! {sudoku_byte, -1}
    end.

waiting(Reader, Timeout) ->
    receive
        {sudoku_byte, Byte} -> Byte
    after 0 ->
        %% Nothing waiting to be read. A reader that has finished has said
        %% its last word already, so waiting on it would be waiting for
        %% ever; input has run out, which is what -1 means.
        case is_process_alive(Reader) of
            false -> -1;
            true -> lingering(Reader, Timeout)
        end
    end.

lingering(Reader, Timeout) ->
    receive
        {sudoku_byte, Byte} -> Byte
    after Timeout ->
        case is_process_alive(Reader) of
            true -> -2;
            false -> -1
        end
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
