%% Entry point for the packaged single-file executable.
%%
%% escript calls main/1 and Gleam generates main/0, so this is the line that
%% joins them. It lives in src/ rather than in scripts/ because it has to be
%% compiled into the application like any other module: the package is built
%% out of what `gleam export erlang-shipment` produced, and nothing outside
%% that shipment is in it.
%%
%% It also hands the arguments over, which is the part that is not
%% bookkeeping. `init:get_plain_arguments/0` is where the game reads them
%% under `gleam run`, and it answers under escript too — but it answers with
%% the path the executable was invoked by on the front, which `gleam run`
%% never has. Eighty-one characters is what a puzzle looks like and
%% `./build/sudoku` is not, so a packaged game started with no arguments at
%% all would refuse its own name and print the usage instead of dealing
%% anything. main/1 is handed exactly the words that were typed, so that is
%% what gets passed on.
-module(sudoku_escript).

-export([main/1]).

main(Arguments) ->
    sudoku_ffi:typed(Arguments),
    sudoku:main().
