//// Drawing the board.
////
//// A frame is built as a list of single lines and printed in one write, so
//// the screen never tears. Each line ends with an erase-to-end-of-line and
//// the frame ends with an erase-to-end-of-screen, which means the previous
//// frame does not have to be cleared first.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/set.{type Set}
import gleam/string
import sudoku/board
import sudoku/editor.{type Editor}
import sudoku/game.{type Game}
import sudoku/generator
import sudoku/term

const empty_cell = "\u{00b7}"

/// Stands in for a cell carrying more than one pencil mark. Which digits
/// those are is spelled out in the status line when the cursor reaches it.
const crowded_cell = "*"

const row_labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I"]

/// How many columns one grid takes up. Cells are two columns wide, so a band
/// of three plus its trailing space is seven, four box rules bring the row to
/// 25, and the row label and its space make 27.
const grid_columns = 27

/// What separates the board from the marks beside it.
const grid_gap = "    "

// Foreground colours.
const given_style = "1;97"

const entered_style = "96"

const conflict_style = "1;91"

const wrong_style = "1;91;4"

const empty_style = "90"

const dim_style = "90"

const title_style = "1;95"

const good_style = "1;92"

const mark_style = "33"

// A wash behind the cells sharing a unit with the cursor, and behind cells
// holding the same digit as the one under the cursor.
const peer_background = "48;5;236"

const match_background = "48;5;238"

const cursor_style = "7"

/// Render the whole screen.
///
/// The help takes over the screen rather than sitting under the board: the
/// two together are taller than a 24-row terminal.
pub fn frame(current: Game) -> String {
  let mode = case current.marking {
    True -> "marking"
    False -> ""
  }
  let head =
    header(generator.origin_label(current.puzzle.origin), mode)
    |> tallied(current)

  case current.show_help {
    True -> term.screen(list.flatten([head, keys(key_reference, mark_notes)]))
    False -> {
      let clashes = board.conflicts(current.board)
      term.screen(
        list.flatten([
          head,
          grids(current, clashes),
          status(current, clashes),
          footer(current),
        ]),
      )
    }
  }
}

/// The title line: what puzzle this is, and which mode it is being worked on
/// in when that is worth saying.
fn header(name: String, mode: String) -> List(String) {
  let badge = case mode {
    "" -> ""
    _ -> term.styled(mark_style, "    " <> mode)
  }

  [
    term.styled(title_style, "S U D O K U")
      <> term.styled(dim_style, "    " <> name)
      <> badge,
    "",
  ]
}

/// Put the count of wrong digits checking has caught on the title line, where
/// the player can see what is left of their allowance before spending it.
///
/// There is nothing to show before checking has been asked for, and nothing
/// worth showing once the game is over: the panel below the board has the
/// last word there.
fn tallied(head: List(String), current: Game) -> List(String) {
  let hidden =
    game.is_finished(current) || { !current.checking && current.mistakes == 0 }

  case head, hidden {
    _, True -> head
    [], _ -> head
    [title, ..rest], False -> {
      let colour = case current.mistakes >= game.mistake_limit {
        True -> conflict_style
        False -> mark_style
      }
      let tally =
        "    checking "
        <> int.to_string(current.mistakes)
        <> "/"
        <> int.to_string(game.mistake_limit)

      [title <> term.styled(colour, tally), ..rest]
    }
  }
}

fn footer(current: Game) -> List(String) {
  case game.is_finished(current) {
    True -> finished(current)
    False -> [term.styled(dim_style, key_hints(current))]
  }
}

// ---------------------------------------------------------------------------
// The grids
// ---------------------------------------------------------------------------

/// The board, and beside it a grid of the same shape holding the pencil
/// marks. Keeping the two apart lets the board stay as compact and readable
/// as it was before there were any marks to show.
fn grids(current: Game, clashes: Set(Int)) -> List(String) {
  let board_grid = grid(fn(index) { board_cell(current, clashes, index) })
  let marks_grid = grid(fn(index) { mark_cell(current, index) })

  [
    caption("board", "marks"),
    ..list.map2(board_grid, marks_grid, fn(left, right) {
      left <> grid_gap <> right
    })
  ]
}

fn caption(left: String, right: String) -> String {
  term.styled(
    dim_style,
    string.pad_end("  " <> left, grid_columns, " ") <> grid_gap <> "  " <> right,
  )
}

/// Lay nine cells out as `│abc │def │ghi │`, with every cell two columns wide
/// so that a highlight reads as a solid block. The column ruler is built with
/// the same helper, which is what keeps it aligned with the cells.
fn banded(cells: List(String), separator: String) -> String {
  cells
  |> list.sized_chunk(3)
  |> list.map(fn(band) { string.concat(band) <> " " })
  |> string.join(separator)
  |> fn(bands) { separator <> bands <> separator }
}

/// One grid, from its column ruler down to its bottom rule. What goes in each
/// cell is left to the caller, which is how the board and the marks beside it
/// come out exactly the same shape.
fn grid(cell: fn(Int) -> String) -> List(String) {
  let ruler =
    board.span(1, board.side)
    |> list.map(fn(column) { " " <> int.to_string(column) })
    |> banded(" ")

  let bands =
    row_labels
    |> list.index_map(fn(label, row) { row_line(cell, row, label) })
    |> list.sized_chunk(3)
    |> list.intersperse([rule("\u{251c}", "\u{253c}", "\u{2524}")])
    |> list.flatten

  list.flatten([
    [term.styled(dim_style, "  " <> ruler)],
    [rule("\u{250c}", "\u{252c}", "\u{2510}")],
    bands,
    [rule("\u{2514}", "\u{2534}", "\u{2518}")],
  ])
}

fn rule(left: String, join: String, right: String) -> String {
  let bar = string.repeat("\u{2500}", 7)
  "  "
  <> term.styled(dim_style, left <> bar <> join <> bar <> join <> bar <> right)
}

fn row_line(cell: fn(Int) -> String, row: Int, label: String) -> String {
  let cells =
    board.span(0, board.side - 1)
    |> list.map(fn(column) { cell(board.at(row, column)) })

  term.styled(dim_style, label)
  <> " "
  <> banded(cells, term.styled(dim_style, "\u{2502}"))
}

/// A cell of the board itself.
fn board_cell(current: Game, clashes: Set(Int), index: Int) -> String {
  let digit = board.value(current.board, index)
  let glyph = case digit {
    0 -> empty_cell
    _ -> int.to_string(digit)
  }

  let focus = board.value(current.board, current.cursor)
  let colour = board_colour(current, clashes, index, digit)

  painted(current.cursor, index, digit != 0 && digit == focus, glyph, colour)
}

/// A cell of the grid of marks: the digit itself where a cell has been given
/// exactly one reading, an asterisk where it has been given several.
fn mark_cell(current: Game, index: Int) -> String {
  let #(glyph, colour) = case board.sorted_marks(current.board, index) {
    [] -> #(empty_cell, empty_style)
    [only] -> #(int.to_string(only), mark_style)
    _ -> #(crowded_cell, mark_style)
  }

  painted(current.cursor, index, False, glyph, colour)
}

/// Two columns: a leading space so that a highlight reads as a solid block,
/// then the character itself.
fn painted(
  cursor: Int,
  index: Int,
  matching: Bool,
  glyph: String,
  colour: String,
) -> String {
  let styles =
    [background(cursor, index, matching), colour]
    |> list.filter(fn(style) { style != "" })
    |> string.join(";")

  term.styled(styles, " " <> glyph)
}

fn board_colour(
  current: Game,
  clashes: Set(Int),
  index: Int,
  digit: Int,
) -> String {
  case
    digit == 0,
    current.checking && game.is_wrong(current, index),
    set.contains(clashes, index),
    board.is_given(current.board, index)
  {
    True, _, _, _ -> empty_style
    _, True, _, _ -> wrong_style
    _, _, True, _ -> conflict_style
    _, _, _, True -> given_style
    _, _, _, _ -> entered_style
  }
}

/// The cursor and the cells it can see are shaded the same way in both grids,
/// which is what ties one to the other.
fn background(cursor: Int, index: Int, matching: Bool) -> String {
  case index == cursor, matching, shares_unit(index, cursor) {
    True, _, _ -> cursor_style
    _, True, _ -> match_background
    _, _, True -> peer_background
    _, _, _ -> ""
  }
}

fn shares_unit(one: Int, other: Int) -> Bool {
  board.row_of(one) == board.row_of(other)
  || board.col_of(one) == board.col_of(other)
  || board.box_of(one) == board.box_of(other)
}

// ---------------------------------------------------------------------------
// Everything below the grids
// ---------------------------------------------------------------------------

fn status(current: Game, clashes: Set(Int)) -> List(String) {
  let facts =
    [
      "empty " <> int.to_string(board.empty_count(current.board)),
      "clashes " <> int.to_string(set.size(clashes)),
      "time " <> clock(game.elapsed_ms(current)),
    ]
    |> string.join("  \u{2502}  ")

  let marks = case cursor_marks(current) {
    "" -> ""
    text -> term.styled(dim_style, "  \u{2502}  ") <> text
  }

  ["", term.styled(dim_style, facts) <> marks, current.message]
}

/// The cursor cell's marks, written out in full. This is where an asterisk in
/// the grid of marks can be read back as the digits behind it.
fn cursor_marks(current: Game) -> String {
  case board.sorted_marks(current.board, current.cursor) {
    [] -> ""
    marks ->
      term.styled(dim_style, cell_name(current.cursor) <> " marked ")
      <> term.styled(
        mark_style,
        marks |> list.map(int.to_string) |> string.join(" "),
      )
  }
}

/// A cell's name as it is labelled on screen, such as `C4`.
fn cell_name(index: Int) -> String {
  let label = case list.drop(row_labels, board.row_of(index)) {
    [letter, ..] -> letter
    [] -> "?"
  }
  label <> int.to_string(board.col_of(index) + 1)
}

fn clock(milliseconds: Int) -> String {
  let seconds = milliseconds / 1000
  pad(seconds / 60) <> ":" <> pad(seconds % 60)
}

fn pad(value: Int) -> String {
  int.to_string(value) |> string.pad_start(2, "0")
}

fn key_hints(current: Game) -> String {
  let digits = case current.marking {
    True -> "1-9 mark"
    False -> "1-9 place"
  }

  [
    "arrows/hjkl move",
    digits,
    "0 clear",
    "m " <> other_mode(current),
    "? help",
    "q quit",
  ]
  |> string.join("  \u{2502}  ")
}

fn other_mode(current: Game) -> String {
  case current.marking {
    True -> "write"
    False -> "mark"
  }
}

const key_reference = [
  #("\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd", "move the cursor"),
  #("1 - 9", "write a digit, or pencil one in while marking"),
  #("0, space, backspace", "clear the cell, or its marks while marking"),
  #("m", "switch between writing and marking"),
  #("u", "undo"),
  #("c", "check for good; a fourth wrong digit forfeits"),
  #("H", "reveal one cell"),
  #("R", "reveal the whole solution"),
  #("n", "start a new puzzle"),
  #("?", "close this help"),
  #("q", "quit"),
]

const mark_notes = [
  "Marks show in the grid beside the board: the digit itself where a cell",
  "has one, an asterisk where it has several. Move onto a cell to read",
  "all of its marks in the status line. Writing a digit rubs out the marks",
  "it rules out, but not while checking is on and the digit is wrong.",
]

/// A key reference, with a paragraph under it. Used for both the game's help
/// and the editor's.
fn keys(
  reference: List(#(String, String)),
  notes: List(String),
) -> List(String) {
  let entries = {
    use #(pressed, meaning) <- list.map(reference)
    "  "
    <> term.styled(entered_style, string.pad_end(pressed, 22, " "))
    <> term.styled(dim_style, meaning)
  }

  list.flatten([
    [term.styled("1", "Keys"), ""],
    entries,
    [""],
    list.map(notes, term.styled(dim_style, _)),
    ["", term.styled(dim_style, "Any key returns to the board.")],
  ])
}

fn finished(current: Game) -> List(String) {
  let headline = case current.ending {
    Some(game.Revealed) -> term.styled(dim_style, "Solution revealed.")
    // However the allowance ran out, saying how many were wrong covers both
    // writing one too many and asking and being told about several.
    Some(game.Forfeited) ->
      term.styled(
        conflict_style,
        int.to_string(current.mistakes) <> " wrong digits: forfeited.",
      )
      <> term.styled(dim_style, "  They are the ones in red.")
    _ ->
      term.styled(good_style, "Solved in " <> clock(game.elapsed_ms(current)))
      <> term.styled(good_style, aside(current.hints))
  }

  ["", headline, term.styled(dim_style, "n new puzzle  \u{2502}  q quit")]
}

fn aside(hints: Int) -> String {
  case hints {
    0 -> "!"
    1 -> ", with one hint."
    _ -> ", with " <> int.to_string(hints) <> " hints."
  }
}

// ---------------------------------------------------------------------------
// Typing a puzzle in
// ---------------------------------------------------------------------------

/// The editor's screen: one grid, since a puzzle being typed in has no marks
/// yet, drawn by the same code as the board so that the two look alike.
pub fn editor_frame(current: Editor) -> String {
  let head = header(generator.origin_label(generator.Handwritten), "editing")

  case current.show_help {
    True ->
      term.screen(
        list.flatten([head, keys(editor_key_reference, editor_notes)]),
      )
    False -> {
      let clashes = board.grid_conflicts(current.clues)
      term.screen(
        list.flatten([
          head,
          [term.styled(dim_style, "  clues")],
          grid(fn(index) { clue_cell(current, clashes, index) }),
          editor_status(current, clashes),
          [term.styled(dim_style, editor_key_hints)],
        ]),
      )
    }
  }
}

/// A cell being typed in. Clues are drawn the way they will look once the
/// game starts, so what is on screen is what will be played.
fn clue_cell(current: Editor, clashes: Set(Int), index: Int) -> String {
  let digit = editor.value(current, index)
  let glyph = case digit {
    0 -> empty_cell
    _ -> int.to_string(digit)
  }

  let colour = case digit == 0, set.contains(clashes, index) {
    True, _ -> empty_style
    _, True -> conflict_style
    _, _ -> given_style
  }

  let focus = editor.value(current, current.cursor)
  painted(current.cursor, index, digit != 0 && digit == focus, glyph, colour)
}

fn editor_status(current: Editor, clashes: Set(Int)) -> List(String) {
  let facts =
    [
      "clues " <> int.to_string(editor.clue_count(current)),
      "clashes " <> int.to_string(set.size(clashes)),
      "cell " <> cell_name(current.cursor),
    ]
    |> string.join("  \u{2502}  ")

  ["", term.styled(dim_style, facts), current.message]
}

const editor_key_hints = "arrows/hjkl move  \u{2502}  1-9 type  \u{2502}  0 gap  \u{2502}  p play  \u{2502}  ? help  \u{2502}  q quit"

const editor_key_reference = [
  #("\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd", "move the cursor"),
  #("1 - 9", "type a clue in and step on to the next cell"),
  #("0, space, backspace", "leave the cell empty and step on"),
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
]
