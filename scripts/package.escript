#!/usr/bin/env escript
%%! -noshell
-include_lib("kernel/include/file.hrl").

%% Package the game as one self-contained executable.
%%
%% The result is an escript: a zip of every compiled module with a shebang
%% and a line of emulator flags on the front of it. It needs Erlang on the
%% machine that runs it, but not Gleam, not rebar, and not this repository —
%% which is the whole point, a game being a thing somebody should be able to
%% play without first agreeing to install a compiler.
%%
%% +Bc is baked into the emulator arguments deliberately, and it is the only
%% thing here that is a decision rather than plumbing. Without it the BEAM's
%% own break handler takes Ctrl-C and paints its menu over the board; with
%% it, the byte arrives at the game, which has always believed 0x03 means
%% quit and can finally be right about that. The flag belongs in the
%% executable rather than in a wrapper script beside it, because a wrapper is
%% a thing somebody can lose on the way to their PATH.
main([Shipment, Output]) ->
    Files = beam_files(Shipment),
    case Files of
        [] ->
            io:format(standard_error, "no compiled modules under ~s~n", [Shipment]),
            halt(1);
        _ ->
            {ok, {_Name, Archive}} =
                zip:create("sudoku.zip", Files, [memory, {cwd, Shipment}]),
            ok = escript:create(Output, [
                shebang,
                {emu_args, "+Bc -escript main sudoku_escript"},
                {archive, Archive}
            ]),
            ok = file:change_mode(Output, 8#755),
            {ok, #file_info{size = Size}} = file:read_file_info(Output),
            io:format("~s  (~p modules, ~p KB)~n",
                      [Output, length(Files), Size div 1024])
    end;
main(_) ->
    io:format(standard_error, "usage: package.escript <shipment-dir> <output>~n", []),
    halt(1).

%% Every compiled file, named relative to the shipment directory — which is
%% the app/ebin layout the code server goes looking for inside an archive,
%% and it will find nothing at all if the names are absolute.
beam_files(Shipment) ->
    Prefix = Shipment ++ "/",
    [relative(Path, Prefix)
     || Path <- filelib:wildcard(filename:join([Shipment, "*", "ebin", "*"]))].

relative(Path, Prefix) ->
    case string:prefix(Path, Prefix) of
        nomatch -> Path;
        Rest -> Rest
    end.
