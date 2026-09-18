//// The help: the keys, how the game is started, and a page on each way of
//// working a digit out.
////
//// This is mostly writing. The key tables, the words that explain a
//// technique and the small boards that show one at work are all content, and
//// content that has grown by a page every time the game learned something
//// new. Keeping it beside the code that draws the board made both harder to
//// find.
////
//// The examples are drawn by hand rather than lifted out of a real grid. A
//// real one comes with sixty other cells to look past, and the whole point of
//// a page is the one thing it is about.

import gleam/int
import gleam/list
import gleam/string
import sudoku/board
import sudoku/game
import sudoku/grids
import sudoku/logic
import sudoku/palette
import sudoku/practice
import sudoku/term

/// Getting about the board, and putting things on it.
const board_keys = [
  #(
    "\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd",
    "move the cursor; Home and End for the row's ends",
  ),
  #("Tab, Shift-Tab", "to the next cell left empty, or the one before"),
  #("1 - 9", "write a digit, or pencil one in while marking"),
  #("0, space, backspace", "clear the cell, or its marks while marking"),
  #("u", "undo"),
  #("r", "do it again"),
  #("?", "close this help"),
  #("q", "quit, keeping a game in progress"),
  #("Ctrl-L", "draw the screen again"),
]

const board_notes = [
  "Clues are fixed and cannot be written over. A digit that clashes with one",
  "already in its row, column or box turns red and is struck through as it",
  "lands, so a clash says so by its shape as well as by its colour.",
  "",
  "The cells sharing a row, column or box with the cursor are shaded, and so",
  "are the cells holding the digit it stands on. Tab goes to the next blank.",
]

/// Pencilling, which is its own page because it is its own half of the game:
/// every technique past a naked single is an argument about candidates.
const marking_keys = [
  #("m", "switch between writing and marking"),
  #("M then 1 - 9", "pencil one digit in, or rub it out"),
  #("f", "pencil the candidates in; warns of a dead cell"),
  #("S then 1 - 9", "mark out where that digit can go; S again stops"),
]

/// How the game can be started, which the help says and the command line
/// says back when it is handed something it does not know. One list, so that
/// the two cannot come to disagree.
pub const invocations = [
  #("gleam run", "choose a puzzle from the menu"),
  #("gleam run -- hard", "deal one at that difficulty"),
  #("gleam run -- custom", "type a puzzle in"),
  #("gleam run -- resume", "pick up the game you left"),
  #("gleam run -- <puzzle>", "play that puzzle"),
  #("gleam run -- --plain", "draw without colour"),
  #("gleam run -- --help", "say all this and stop"),
]

/// The ways of being handed a puzzle that somebody else had, or that you had
/// yesterday. A list of their own because they share a page of their own,
/// the everyday ones having filled the one before it.
pub const repeating_invocations = [
  #("gleam run -- daily", "the puzzle everybody gets today"),
  #("gleam run -- daily 2026-09-17", "the one belonging to that day"),
  #("gleam run -- hard --seed 7", "deal the puzzle that seed deals"),
]

/// Every way in, which is what the command line answers with and what the
/// two pages between them show.
pub fn every_invocation() -> List(#(String, String)) {
  list.append(invocations, repeating_invocations)
}

const starting_notes = [
  "A puzzle is 81 characters, a digit for each clue and a dot for each blank;",
  "the game prints the one it was playing as it leaves, to hand on or hand back.",
  "",
  "--plain drops the colours and keeps the shapes, and can be given alongside",
  "a puzzle. Setting NO_COLOR in the environment does the same thing.",
]

const repeating_notes = [
  "Every deal is carved from a seed, and the game says which as it leaves. A",
  "seed handed back beside a difficulty deals that same puzzle. --seed=7 says",
  "it the other way round, and either wants a difficulty beside it: a seed",
  "names a deal rather than a grid.",
  "",
  "The daily is one puzzle a day and everybody gets the same one, so it cannot",
  "ask which difficulty you fancied. It ramps through the week instead — an",
  "easy Monday, and a Sunday that is an afternoon — and the menu says which",
  "day it is offering and how hard that makes it.",
  "",
  "Its times are kept apart from the levels', one to a day, and the first run",
  "at a day is the one written down: a day played twice is a day you have",
  "already seen the answer to.",
]

/// The same, for a terminal that has not been taken over.
pub fn usage() -> String {
  // Wide enough for the longest of them, worked out rather than written
  // down: a line added here should not be able to run into its meaning.
  let column =
    list.fold(every_invocation(), 24, fn(widest, entry) {
      int.max(widest, string.length(entry.0) + 2)
    })

  let lines = {
    use #(invocation, meaning) <- list.map(every_invocation())
    "  " <> string.pad_end(invocation, column, " ") <> meaning
  }

  string.join(["Usage:", ..lines], "\n")
}

/// Asking the game for something, and leaving.
const asking_keys = [
  #("c c", "check for good; a fourth wrong digit forfeits"),
  #("H", "take the next step, and say why"),
  #("t", "on a practice grid, talk me through the next step"),
  #("R", "reveal the whole solution, on a second R"),
  #("p", "pause: put the board away and stop the clock"),
  #("X", "start this puzzle again, on a second X"),
  #("n", "start a new puzzle"),
]

const ask_notes = [
  "Checking and a first hint both say what they will cost before they do it;",
  "press the key again to go ahead. Either one makes the game an aided one,",
  "which is not timed, and checking once on cannot be turned off again.",
  "",
  "A hint takes the cell you are on whenever it can be worked out, and names",
  "the technique that settled it. There is a page on each of those further on.",
  "",
  "On a practice grid t talks you through whatever the next step is, a nudge",
  "at a time, and never plays it, so the grid teaches all it needs, not one.",
]

const mark_notes = [
  "Marks show in the grid beside the board: the digit itself where a cell has",
  "one, an asterisk where it has several, and all of them in the status line.",
  "Writing a digit rubs out the marks it rules out, unless checking is on and",
  "the digit is wrong. M and a digit pencils one in without leaving writing,",
  "and shift and a digit does the same in one keystroke, where the game can",
  "read your number row. S and a digit shades every cell that digit could",
  "still go in, read off the grid rather than off your marks — what you have",
  "pencilled is your reasoning, and reasoning can be wrong.",
]

/// A key reference, with a paragraph under it. Used for both the game's help
/// and the editor's.
fn key_table(
  title: String,
  reference: List(#(String, String)),
  notes: List(String),
) -> List(String) {
  // Wide enough for the longest of them, and never so narrow that the pages
  // stop looking like one another.
  let column =
    list.fold(reference, 22, fn(widest, entry) {
      int.max(widest, string.length(entry.0) + 2)
    })

  let entries = {
    use #(pressed, meaning) <- list.map(reference)
    "  "
    <> term.styled(palette.entered(), string.pad_end(pressed, column, " "))
    <> term.styled(palette.dim(), meaning)
  }

  list.flatten([
    [term.styled("1", title), ""],
    entries,
    [""],
    list.map(notes, term.styled(palette.dim(), _)),
  ])
}

// ---------------------------------------------------------------------------
// The help, page by page
// ---------------------------------------------------------------------------

/// The keys on the first page, and then a page on each way of working a digit
/// out: what it is, a small board showing it happening, and what it settles.
///
/// The examples are drawn by hand rather than lifted out of a real grid. A
/// real one comes with sixty other cells to look past, and the whole point of
/// a page is the one thing it is about.
pub fn page(page: game.Help) -> List(String) {
  let body = case page {
    game.Keys -> key_table("Keys: the board", board_keys, board_notes)
    game.Marking -> key_table("Keys: pencil marks", marking_keys, mark_notes)
    game.Asking ->
      key_table("Keys: asking, and finishing", asking_keys, ask_notes)
    game.Starting -> key_table("Starting up", invocations, starting_notes)
    game.Repeating ->
      key_table(
        "Starting up: the same puzzle twice",
        repeating_invocations,
        repeating_notes,
      )
    game.About(technique) -> about(technique)
  }

  list.append(body, ["", getting_about(page)])
}

/// The line along the bottom of a page: how to turn them, how to leave, and
/// on a page about a technique, where to go and meet one.
///
/// A page read and never used is a page wasted, and an X-wing turns up in
/// about one dealt Expert puzzle in fifteen — waiting for one to come round
/// is not a plan. There is a grid kept that cannot be finished without it,
/// and this says which two keys reach it.
fn getting_about(page: game.Help) -> String {
  let turning =
    term.styled(
      palette.dim(),
      "\u{2190} \u{2192}  " <> paging(page) <> "     any other key returns",
    )

  case page {
    game.About(technique) ->
      turning
      <> term.styled(palette.dim(), "     practise it: ")
      <> term.styled(palette.key(), int.to_string(practice.choice()))
      <> term.styled(palette.dim(), " then ")
      <> term.styled(palette.key(), int.to_string(at(technique)))
    _ -> turning
  }
}

fn paging(page: game.Help) -> String {
  let pages = game.pages()
  let at = list.length(list.take_while(pages, fn(other) { other != page })) + 1

  "page " <> int.to_string(at) <> " of " <> int.to_string(list.length(pages))
}

fn about(technique: logic.Technique) -> List(String) {
  let #(what, example, so) = teaching(technique)

  list.flatten([
    [term.styled("1", capitalised(logic.label(technique))), ""],
    list.map(what, term.styled(palette.dim(), _)),
    [""],
    example,
    [""],
    [term.styled(palette.entered(), so)],
  ])
}

/// Where this technique sits on the screen that offers them.
fn at(technique: logic.Technique) -> Int {
  let before =
    list.take_while(practice.techniques(), fn(other) { other != technique })
  list.length(before) + 1
}

fn capitalised(name: String) -> String {
  string.uppercase(string.slice(name, 0, 1))
  <> string.slice(name, 1, string.length(name) - 1)
}

/// What each technique is, what it looks like, and what it settles.
///
/// The strips show what the cells of one unit have left in them. The maps
/// show one digit at a time: where it can still go, and where this way of
/// looking at it has just shut it out.
fn teaching(
  technique: logic.Technique,
) -> #(List(String), List(String), String) {
  case technique {
    logic.NakedSingle -> #(
      [
        "A cell with one candidate left has to take it. Everything else that",
        "could have gone there is already spoken for by a peer.",
      ],
      strip("C", ["18", "4", "79", "28", "3", "5", "18", "6", "79"], [4], []),
      "C5 has one candidate left, so that is what it is: a 3.",
    )

    logic.HiddenSingle -> #(
      [
        "A digit with one cell left in a unit has to go there, however much",
        "else that cell could still have taken.",
      ],
      strip(
        "C",
        ["27", "279", "89", "89", "1279", "27", "89", "89", "279"],
        [4],
        [],
      ),
      "Only C5 can take a 1, so that is where the row's 1 goes.",
    )

    logic.LockedCandidates -> #(
      [
        "A digit shut into one line of a box has to be somewhere along that",
        "line, so it cannot be anywhere else along it.",
      ],
      // The left box can only take its 1 in row A, so the rest of row A
      // cannot have one. A hash is a cell the digit can still go in, a bang
      // one this has just shut it out of.
      map("1", ["##.!.!.!.", "....#.#..", ".....#..#"], True),
      "Every 1 in the left box is in row A, so A4, A6 and A8 lose theirs.",
    )

    logic.NakedPair -> #(
      [
        "Two cells in a unit holding the same two candidates take one each",
        "between them, whichever way round, so nothing else can have either.",
      ],
      strip("C", ["79", "4", "79", "1379", "3", "5", "8", "6", "2"], [0, 2], [3]),
      "C1 and C3 take 7 and 9, so C4 is down to a 1 or a 3.",
    )

    logic.HiddenPair -> #(
      [
        "Two digits in a unit with the same two cells to go in take one each,",
        "so those two cells can hold nothing else.",
      ],
      strip(
        "C",
        ["123", "34", "124", "34", "5", "6", "7", "8", "9"],
        [0, 2],
        [],
      ),
      "Only C1 and C3 can take a 1 or a 2, so both lose their other digits.",
    )

    logic.NakedTriple -> #(
      [
        "Three cells between them holding three candidates take one each, on",
        "the same reasoning as two cells holding two.",
      ],
      strip(
        "C",
        ["27", "79", "29", "1", "2579", "6", "8", "3", "4"],
        [0, 1, 2],
        [4],
      ),
      "C1, C2 and C3 take 2, 7 and 9, so C5 has to be the 5.",
    )

    logic.XWing -> #(
      [
        "A digit down to the same two columns in two rows takes one corner in",
        "each row, and so one in each column. Or the other way about.",
      ],
      // Rows B and F can only take their 9 in column 2 or column 9. The
      // corners make a rectangle, and every other 9 in those two columns
      // has to go.
      map(
        "9",
        [
          ".!.......", ".#......#", "........!", ".........", ".!.......",
          ".#......#", ".........", "........!", ".........",
        ],
        False,
      ),
      "The 9s in rows B and F keep to columns 2 and 9, so four others go.",
    )

    logic.XYWing -> #(
      [
        "A cell of two candidates, and two more it can see holding one of",
        "those apiece alongside a third: the third has nowhere left to hide.",
      ],
      // B2 is a 2 or a 7. If it is the 2, E2 has to be the 9; if it is the
      // 7, B7 has to be. Either way one of the wings is a 9, and E7 can see
      // them both.
      wings([#("B2", "27"), #("B7", "79"), #("E2", "29")], ["E7"], "9"),
      "One of B7 and E2 is a 9 whichever way B2 falls, so E7 loses its 9.",
    )

    logic.Swordfish -> #(
      [
        "The same argument as an X-wing over three lines instead of two: a",
        "digit down to three columns in three rows takes one in each.",
      ],
      // Rows A, D and G can only take their 7 in columns 1, 4 and 8 — two
      // of the three apiece, and not the same two. The three columns are
      // spoken for all the same.
      map(
        "7",
        [
          "#..#.....", "!........", "...!.....", "...#...#.", ".......!.",
          ".........", "#......#.", "!........", ".........",
        ],
        False,
      ),
      "The 7s in rows A, D and G keep to columns 1, 4 and 8, so four go.",
    )
  }
}

/// A board with a few cells' candidates written into them, for a technique
/// whose argument is not read off one unit and so cannot be drawn as a
/// strip.
///
/// Cells are three columns wide rather than two, a pair of candidates
/// needing the room. Everything not named is a dot, the same as everywhere
/// else: the whole point of a page is the one thing it is about, and a board
/// with sixty other cells filled in is a board to look past.
fn wings(
  held: List(#(String, String)),
  out: List(String),
  digit: String,
) -> List(String) {
  let width = 3

  let ruler =
    "    "
    <> term.styled(
      palette.dim(),
      grids.chunked(
        list.map(board.span(1, 9), fn(column) { "  " <> int.to_string(column) }),
        9,
        " ",
      ),
    )

  let lines = {
    use row <- list.map(board.span(0, 8))
    let cells = {
      use column <- list.map(board.span(0, 8))
      let name = board.name(board.at(row, column))

      case list.key_find(held, name), list.contains(out, name) {
        Ok(pair), _ -> term.styled(palette.given(), " " <> pair)
        _, True -> term.styled(palette.conflict(), "  " <> digit)
        _, False -> term.styled(palette.empty(), "  \u{b7}")
      }
    }

    "  "
    <> term.styled(palette.dim(), board.row_letter(row))
    <> " "
    <> grids.chunked(cells, 9, term.styled(palette.dim(), "\u{2502}"))
  }

  // Not `banded_rule`, which measures itself for cells two columns wide.
  // One band of nine cells of `width`, and the space that closes the row.
  let rules = fn(left, right) {
    "    "
    <> term.styled(
      palette.dim(),
      left <> string.repeat("\u{2500}", 9 * width + 1) <> right,
    )
  }

  list.flatten([
    [ruler],
    [rules("\u{250c}", "\u{2510}")],
    lines,
    [rules("\u{2514}", "\u{2518}")],
  ])
}

/// One unit's worth of cells and what each of them has left in it.
fn strip(
  label: String,
  cells: List(String),
  lit: List(Int),
  out: List(Int),
) -> List(String) {
  let wall = term.styled(palette.dim(), "\u{2502}")
  let wide = 5

  let ruler =
    "    "
    <> term.styled(
      palette.dim(),
      " "
        <> {
        use column <- list.map(board.span(1, 9))
        centred(int.to_string(column), wide) <> " "
      }
      |> string.concat,
    )

  let rules = fn(left, join, right) {
    "    "
    <> term.styled(
      palette.dim(),
      left
        <> {
        list.repeat(string.repeat("\u{2500}", wide), 9) |> string.join(join)
      }
        <> right,
    )
  }

  let row =
    "  "
    <> term.styled(palette.dim(), label)
    <> " "
    <> wall
    <> {
      use cell, at <- list.index_map(cells)
      let colour = case list.contains(lit, at), list.contains(out, at) {
        True, _ -> palette.given()
        _, True -> palette.conflict()
        _, _ -> palette.empty()
      }
      term.styled(colour, centred(cell, wide)) <> wall
    }
    |> string.concat

  [
    ruler,
    rules("\u{250c}", "\u{252c}", "\u{2510}"),
    row,
    rules("\u{2514}", "\u{2534}", "\u{2518}"),
  ]
}

/// Where one digit can still go, drawn as the board is drawn: `#` for a cell
/// it can take, `!` for one this reasoning has just shut it out of, and a dot
/// for the rest.
///
/// Box rules are drawn only where the technique is about boxes. For one about
/// rows and columns they are three lines of noise, and three lines is the
/// difference between the page fitting and not.
fn map(digit: String, rows: List(String), boxed: Bool) -> List(String) {
  let size = case boxed {
    True -> 3
    False -> 9
  }

  let ruler =
    "    "
    <> term.styled(
      palette.dim(),
      grids.chunked(
        list.map(board.span(1, 9), fn(column) { " " <> int.to_string(column) }),
        size,
        " ",
      ),
    )

  let lines = {
    use line, at <- list.index_map(rows)
    let cells = {
      use marker <- list.map(string.to_graphemes(line))
      case marker {
        "#" -> term.styled(palette.given(), " " <> digit)
        "!" -> term.styled(palette.conflict(), " " <> digit)
        _ -> term.styled(palette.empty(), " \u{b7}")
      }
    }

    "  "
    <> term.styled(palette.dim(), board.row_letter(at))
    <> " "
    <> grids.chunked(cells, size, term.styled(palette.dim(), "\u{2502}"))
  }

  let rules = fn(left, join, right) {
    grids.banded_rule(left, join, right, size, "    ")
  }

  list.flatten([
    [ruler],
    [rules("\u{250c}", "\u{252c}", "\u{2510}")],
    lines,
    [rules("\u{2514}", "\u{2534}", "\u{2518}")],
  ])
}

/// Text in the middle of a field that wide, leaning left where it cannot sit
/// exactly in the middle.
fn centred(text: String, wide: Int) -> String {
  let left = { wide - string.length(text) + 1 } / 2
  string.pad_end(string.repeat(" ", left) <> text, wide, " ")
}

// ---------------------------------------------------------------------------
// The editor's own help
// ---------------------------------------------------------------------------

/// One page, since typing a puzzle in has fewer keys and no techniques.
pub fn editor_keys() -> List(String) {
  key_table("Keys", editor_key_reference, editor_notes)
}

const editor_key_reference = [
  #(
    "\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd",
    "move the cursor; Home and End for the row's ends",
  ),
  #("1 - 9", "type a clue in and step on to the next cell"),
  #("0, space, . or _", "leave the cell empty and step on"),
  #("u", "undo"),
  #("x", "clear the grid and start over"),
  #("p", "play the puzzle"),
  #("n", "back to the menu"),
  #("?", "close this help"),
  #("q", "quit"),
]

const editor_notes = [
  "Digits step the cursor on by themselves, so a row is nine keystrokes and",
  "the whole grid eighty-one, read straight off the page. Clues that clash",
  "turn red, and p checks the puzzle has exactly one answer before play.",
  "",
  "Since a dot counts as a blank, a whole puzzle can be pasted in as the",
  "81-character line this game prints on its way out.",
]
