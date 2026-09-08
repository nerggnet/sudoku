# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run
```

Pick a difficulty, then play. Puzzles are generated fresh each time and always
have exactly one solution. Or pick `Custom` and type a puzzle in yourself, out
of a newspaper.

```
 S U D O K U    Medium    marking

   board                          marks
     1 2 3   4 5 6   7 8 9          1 2 3   4 5 6   7 8 9
   ┌───────┬───────┬───────┐      ┌───────┬───────┬───────┐
 A │ · · 1 │ 8 3 · │ 9 5 · │    A │ * · · │ · · · │ · · · │
 B │ · · · │ 9 · · │ 7 3 6 │    B │ · · · │ · · · │ · · · │
 C │ · · 7 │ · · · │ · 8 · │    C │ · · · │ · · · │ · · · │
   ├───────┼───────┼───────┤      ├───────┼───────┼───────┤
 D │ · · 3 │ 2 1 · │ · 4 · │    D │ 7 · · │ · · · │ · · · │
 E │ 9 2 8 │ · · · │ 3 1 7 │    E │ · · · │ · · · │ · · · │
 F │ · 5 · │ · 7 9 │ 6 · · │    F │ · · · │ · · · │ · · · │
   ├───────┼───────┼───────┤      ├───────┼───────┼───────┤
 G │ · 1 · │ · · · │ 8 · · │    G │ · · · │ · · · │ · · · │
 H │ 4 7 9 │ · · 3 │ · · · │    H │ · · · │ · · · │ · · · │
 I │ · 3 2 │ · 5 6 │ 4 · · │    I │ · · · │ · · · │ · · · │
   └───────┴───────┴───────┘      └───────┴───────┴───────┘

 empty 45  │  clashes 0  │  time 00:00  │  A1 marked 1 3 5
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

## Typing a puzzle in

`Custom` on the menu opens an empty grid to type a puzzle into instead of
dealing one:

```
 S U D O K U    Custom    editing

   clues
     1 2 3   4 5 6   7 8 9
   ┌───────┬───────┬───────┐
 A │ 5 3 · │ · 7 · │ · · · │
 B │ 6 · · │ 1 9 5 │ · · · │
 C │ · 9 8 │ · · · │ · 6 · │
   ├───────┼───────┼───────┤
 D │ 8 · · │ · 6 · │ · · 3 │
 E │ 4 · · │ 8 · 3 │ · · 1 │
 F │ 7 · · │ · 2 · │ · · 6 │
   ├───────┼───────┼───────┤
 G │ · 6 · │ · · · │ 2 8 · │
 H │ · · · │ 4 1 9 │ · · 5 │
 I │ · · · │ · 8 · │ · 7 9 │
   └───────┴───────┴───────┘

 clues 30  │  clashes 0  │  cell A1
 arrows/hjkl move  │  1-9 type  │  0 gap  │  p play  │  ? help  │  q quit
```

The cursor steps on by itself after every key, so a row is nine keystrokes and
the whole grid eighty-one, read straight off the page. `0` or space leaves a
gap; the arrow keys go back over anything mistyped.

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `1`–`9` | type a clue in and step on to the next cell |
| `0`, space, backspace | leave the cell empty and step on |
| `u` | undo |
| `x` | clear the grid and start over |
| `p` | play the puzzle |
| `n` | back to the menu |
| `?` | help |
| `q` | quit |

`p` starts the game, but only once the clues hold together. Two of the same
digit in a row, column or box turn red as they are typed, and the puzzle has
to have exactly one answer before it can be played — the game needs to know
the answer for checking and hints, and insisting on one catches the usual
slips in copying a puzzle down. A mistyped digit leaves the grid with no
answer at all, and a missed one leaves it with several; either way the status
line says which it is and the clues stay put to be fixed.

Once play starts, a typed-in puzzle is like any other: the clues are fixed,
and undo, marks, checking, hints and the clock all work the same. The header
says `Custom` where it would otherwise name a difficulty.

## Pencil marks

Press `m` to switch to marking, then `1`–`9` to pencil candidates into a cell
and the same key again to rub one out. `m` switches back to writing digits;
the header and the key hints along the bottom say which mode you are in.

Marks get a grid of their own beside the board rather than being squeezed into
it, which leaves the board as compact and readable as it was without them. The
two grids are the same shape and share the cursor and its shading, so a cell in
one is easy to find in the other. A cell given a single reading shows that
digit; a cell given several shows `*`. Move onto it and the status line spells
its marks out in full:

```
 empty 45  │  clashes 0  │  time 00:00  │  A1 marked 1 3 5
```

Writing a digit tidies up after itself: the cell's own marks go, and so does
that digit's mark in every cell that can see it. Not while checking is on and
the digit is wrong, though — the marks around a digit the game is calling out
in the same breath are the reasoning you need to put it right, so they stay
where they are. Erasing a digit leaves marks alone too, so taking back a
wrong guess does not cost you the reasoning behind it. Undo covers marks as
well as digits.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, pencil marks, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/game` | game state and what each key does to it |
| `sudoku/editor` | typing a puzzle in by hand |
| `sudoku/render` | drawing a frame |
| `sudoku/key` | decoding bytes into keystrokes |
| `sudoku/term` | raw input and ANSI escapes |

Pencil marks live on the board rather than in the game around it, which is
what lets undo capture them without any extra bookkeeping. Both grids come out
of one function that takes the cell renderer as an argument, so they cannot
drift apart in shape, and the editor draws its grid with the same function
again.

A puzzle carries where it came from, `Dealt(difficulty)` or `Handwritten`,
which is all that separates a typed-in puzzle from a generated one once play
begins. Generating one carves clues out of a solution; typing one in works the
other way round, solving the clues to find the answer the game will check
against, and refusing them if there is not exactly one.

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
