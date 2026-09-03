# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run
```

Pick a difficulty, then play. Puzzles are generated fresh each time and always
have exactly one solution.

```
 S U D O K U    Medium    marking

        1    2    3      4    5    6      7    8    9
   ┌────────────────┬────────────────┬────────────────┐
 A │ 123+    ·    1 │    5    ·    · │    4    3    · │
 B │    ·    ·    5 │    ·    ·    · │    7    ·    · │
 C │    6    ·    7 │    4    ·    1 │    ·    5    8 │
   ├────────────────┼────────────────┼────────────────┤
 D │    3    7    · │    9    ·    · │    ·    6    4 │
 E │    ·    ·    · │    8    ·    6 │    ·    ·    · │
 F │    5    9    · │    ·    ·    7 │    ·    8    3 │
   ├────────────────┼────────────────┼────────────────┤
 G │    2    6    · │    7    ·    8 │    3    ·    9 │
 H │    ·    ·    3 │    ·    ·    · │    6    ·    · │
 I │    ·    5    9 │    ·    ·    4 │    8    ·    · │
   └────────────────┴────────────────┴────────────────┘

 empty 45  │  clashes 0  │  time 00:00  │  A1 marked 1 2 3 4 5
```

## Keys

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `1`–`9` | write a digit, or pencil one in while marking |
| `0`, space, backspace | clear the cell, or its marks while marking |
| `m` | switch between writing and marking |
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

## Pencil marks

Press `m` to switch to marking, then `1`–`9` to pencil candidates into a cell
and the same key again to rub one out. `m` switches back to writing digits;
the header and the key hints along the bottom say which mode you are in.

Marks are amber and sit against the left of their cell, while answers are
white or cyan and sit against the right, so a cell marked with a single digit
can never be mistaken for a solved one even without colour. Four marks fit in
a cell; beyond that the cell shows `123+` and the status line spells the
cursor cell's marks out in full, so nothing you wrote is ever out of reach.

Writing a digit tidies up after itself: the cell's own marks go, and so does
that digit's mark in every cell that can see it. Erasing a digit leaves marks
alone, so taking back a wrong guess does not cost you the reasoning behind it.
Undo covers marks as well as digits.

Marks are display-limited by width, not by the model — a cell can hold all
nine. Showing more of them inline is one constant, `content_width` in
`sudoku/render`: at four the grid is 55 columns wide, at nine it is 91.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, pencil marks, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/game` | game state and what each key does to it |
| `sudoku/render` | drawing a frame |
| `sudoku/key` | decoding bytes into keystrokes |
| `sudoku/term` | raw input and ANSI escapes |

Pencil marks live on the board rather than beside it, which is what lets undo
capture them without any extra bookkeeping.

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
