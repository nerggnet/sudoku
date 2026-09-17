%% Small Erlang shim for the bits of terminal and randomness handling that
%% Gleam's standard library does not cover.
-module(sudoku_ffi).

-export([enable_raw/0, read_byte/0, read_byte_after/1, now_ms/0, shuffle/1]).
-export([remembered/2]).
-export([seed/1, fresh_seed/0]).
-export([today/0, day_of_week/3, valid_date/3]).
-export([file_path/1, write_file/2, read_file/1, forget_file/1, kept_files/1]).
-export([new_id/0]).
-export([arguments/0, columns/0, rows/0]).
-export([plain/0, set_plain/1]).
-export([protected/2, stop/1]).

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

%% Stop, with something to say about how it went: nothing wrong is 0, and
%% a command line that could not be read is 1. Output written first still
%% arrives, halt/1 flushing on its way out.
stop(Status) ->
    erlang:halt(Status).

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
        try Restore() catch _:_ -> nil end
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

%% Remember the answer to a question that always has the same answer.
%%
%% The shape of the grid is a fact about Sudoku rather than about any one
%% puzzle: which cells make up a row, and which cells a given cell can see,
%% are the same on an empty grid as on a finished one. Working them out
%% afresh is what dealing a puzzle used to spend most of its time on —
%% carving one Expert grid asked for the nine rows forty-five thousand times
%% over and got the same nine rows back every time.
%%
%% persistent_term rather than a process dictionary or an ets table, because
%% this is written once and then only ever read: a read costs nothing and
%% hands back the term itself rather than a copy of it, which is exactly the
%% bargain on offer. The write it makes in exchange is expensive, and there
%% are a handful of them in the life of the game.
remembered(Key, Work) ->
    case persistent_term:get({sudoku_table, Key}, undefined) of
        undefined ->
            Value = Work(),
            persistent_term:put({sudoku_table, Key}, Value),
            Value;
        Value ->
            Value
    end.

%% Today, on the wall where the player is sitting.
%%
%% Local rather than UTC. A daily puzzle belongs to somebody's day rather
%% than to a moment, and a player in Stockholm should not be handed
%% tomorrow's puzzle at one in the morning because a server somewhere has
%% already turned over. Two people in different places who want the same
%% grid can name the date outright, which is what naming it is for.
today() ->
    {{Y, M, D}, _} = erlang:localtime(),
    {Y, M, D}.

%% 1 for Monday through 7 for Sunday, which is how the week is counted here
%% and how a daily puzzle knows how hard to be.
day_of_week(Y, M, D) ->
    calendar:day_of_the_week(Y, M, D).

%% Whether those three numbers are a day that happened. February 30th is
%% typed often enough to be worth refusing by name.
valid_date(Y, M, D) ->
    calendar:valid_date(Y, M, D).

now_ms() ->
    erlang:monotonic_time(millisecond).

%% Start the chance in a deal at a named place.
%%
%% Everything chance decides while a puzzle is carved is drawn from here:
%% the order the digits are tried in filling the grid, and the order the
%% cells are taken back out of it. So the same seed carves the same puzzle,
%% and a deal can be asked for a second time.
seed(Seed) ->
    _ = rand:seed(exsss, Seed),
    nil.

%% A seed nobody chose, short enough to read out over a telephone.
%%
%% Not drawn from rand itself, which is the thing being seeded: asked for
%% twice in one run it would hand back the same number the second time, and
%% two puzzles dealt in a sitting would be one puzzle dealt twice.
fresh_seed() ->
    erlang:phash2({erlang:monotonic_time(), erlang:unique_integer()}, 100000000).

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

%% Every file kept under this prefix, with when it was last written, so
%% that games put down can be offered back newest first. The time comes from
%% the file rather than from its name: a name is a guess about what happened
%% and a timestamp is what did.
kept_files(Prefix) ->
    Pattern = filename:join(filename:dirname(kept(Prefix)),
                            binary_to_list(Prefix) ++ "*"),
    [{unicode:characters_to_binary(filename:basename(Path)), modified(Path)}
     || Path <- filelib:wildcard(Pattern)].

modified(Path) ->
    case file:read_file_info(Path, [{time, posix}]) of
        {ok, Info} -> element(6, Info);
        _ -> 0
    end.

%% A name for a game's save file, unique among every game there could be.
%%
%% The second it started on the clock on the wall, which is the part worth
%% reading; the process it is being played in, which separates two terminals;
%% and a count, which separates two games in one terminal started inside the
%% same second — n deals another puzzle faster than that.
new_id() ->
    Parts = [integer_to_list(erlang:system_time(second)),
             os:getpid(),
             integer_to_list(erlang:unique_integer([positive, monotonic]))],
    unicode:characters_to_binary(lists:join("-", Parts)).

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
