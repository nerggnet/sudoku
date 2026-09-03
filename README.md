# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run
```

Pick a difficulty, then play. Puzzles are generated fresh each time and always
have exactly one solution.

```
 S U D O K U    Medium

     1 2 3   4 5 6   7 8 9
   ┌───────┬───────┬───────┐
 A │ · 7 · │ · 4 · │ 8 · · │
 B │ 8 5 3 │ · 7 · │ 4 · 9 │
 C │ 9 · 4 │ · · 2 │ · · · │
   ├───────┼───────┼───────┤
 D │ 6 · · │ 8 · · │ · · 7 │
 E │ 5 8 · │ 6 · 1 │ · 4 2 │
 F │ 3 · · │ · · 7 │ · · 8 │
   ├───────┼───────┼───────┤
 G │ · · · │ 2 · · │ 6 · 4 │
 H │ 4 · 8 │ · 6 · │ 9 3 1 │
 I │ · · 6 │ · 1 · │ · 8 · │
   └───────┴───────┴───────┘

 empty 45  │  clashes 0  │  time 00:00
```

## Keys

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `1`–`9` | write a digit |
| `0`, space, backspace | clear the cell |
| `u` | undo |
| `c` | check what is filled in so far |
| `H` | reveal one cell |
| `R` | reveal the whole solution |
| `n` | start a new puzzle |
| `?` | help |
| `q` | quit |

Clues are fixed and cannot be overwritten. Digits that clash with another in
the same row, column or box turn red as you type them, and the cells sharing a
row, column or box with the cursor are shaded so it is easier to see what a
cell can still be.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/game` | game state and what each key does to it |
| `sudoku/render` | drawing a frame |
| `sudoku/key` | decoding bytes into keystrokes |
| `sudoku/term` | raw input and ANSI escapes |

The solver expands the empty cell with the fewest candidates first, which
keeps the search small enough that generating even an Expert puzzle takes
about a tenth of a second. Generation fills a grid at random, then removes
cells in rotationally symmetric pairs for as long as the puzzle still has
exactly one solution.

Keyboard input needs OTP 26 or later, which is where
`shell:start_interactive({noshell, raw})` arrived. Without it — on older OTP,
or when input is piped rather than typed — the game still runs, but each key
has to be followed by Enter, and it says so on the menu.

## Development

```sh
gleam run   # Play
gleam test  # Run the tests
```
