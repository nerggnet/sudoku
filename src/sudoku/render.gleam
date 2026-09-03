//// Drawing the board.
////
//// A frame is built as a list of single lines and printed in one write, so
//// the screen never tears. Each line ends with an erase-to-end-of-line and
//// the frame ends with an erase-to-end-of-screen, which means the previous
//// frame does not have to be cleared first.

import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string
import sudoku/board
import sudoku/game.{type Game}
import sudoku/generator
import sudoku/term

const empty_cell = "\u{00b7}"

/// How many characters of a cell hold its contents, and so how many pencil
/// marks fit in one. Height is what a terminal is short of, not width: at
/// four the grid is 55 columns across and still only fourteen rows tall.
const content_width = 4

const row_labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I"]

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
  case current.show_help {
    True -> term.screen(list.flatten([header(current), help()]))
    False -> {
      let clashes = board.conflicts(current.board)
      term.screen(
        list.flatten([
          header(current),
          grid(current, clashes),
          status(current, clashes),
          footer(current),
        ]),
      )
    }
  }
}

fn header(current: Game) -> List(String) {
  let marking = case current.marking {
    True -> term.styled(mark_style, "    marking")
    False -> ""
  }

  [
    term.styled(title_style, "S U D O K U")
      <> term.styled(
      dim_style,
      "    " <> generator.label(current.puzzle.difficulty),
    )
      <> marking,
    "",
  ]
}

fn footer(current: Game) -> List(String) {
  case game.is_finished(current) {
    True -> finished(current)
    False -> [term.styled(dim_style, key_hints(current))]
  }
}

// ---------------------------------------------------------------------------
// The grid
// ---------------------------------------------------------------------------

/// Lay nine cells out as `│abc │def │ghi │`. The column ruler is built with
/// the same helper, which is what keeps it aligned with the cells.
fn banded(cells: List(String), separator: String) -> String {
  cells
  |> list.sized_chunk(3)
  |> list.map(fn(band) { string.concat(band) <> " " })
  |> string.join(separator)
  |> fn(bands) { separator <> bands <> separator }
}

fn grid(current: Game, clashes: Set(Int)) -> List(String) {
  let ruler =
    board.span(1, board.side)
    |> list.map(fn(column) { " " <> answer_column(int.to_string(column)) })
    |> banded(" ")

  let bands =
    row_labels
    |> list.index_map(fn(label, row) { row_line(current, clashes, row, label) })
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
  // Three cells to a band, each a leading space wide plus its contents,
  // and the trailing space `banded` puts on the end of the band.
  let bar = string.repeat("\u{2500}", 3 * { content_width + 1 } + 1)
  "  "
  <> term.styled(dim_style, left <> bar <> join <> bar <> join <> bar <> right)
}

fn row_line(
  current: Game,
  clashes: Set(Int),
  row: Int,
  label: String,
) -> String {
  let cells =
    board.span(0, board.side - 1)
    |> list.map(fn(column) { cell(current, clashes, board.at(row, column)) })

  term.styled(dim_style, label)
  <> " "
  <> banded(cells, term.styled(dim_style, "\u{2502}"))
}

/// A cell holds either an answer or a set of pencil marks, never both.
///
/// Answers sit against the right of the cell and marks against the left, so
/// that a cell marked with a single digit still cannot be mistaken for a
/// filled-in one, whatever the terminal does with colour.
fn cell(current: Game, clashes: Set(Int), index: Int) -> String {
  let digit = board.value(current.board, index)

  let text = case digit, board.sorted_marks(current.board, index) {
    0, [] -> answer_column(empty_cell)
    0, marks -> string.pad_end(mark_column(marks), content_width, " ")
    _, _ -> answer_column(int.to_string(digit))
  }

  let styles =
    [
      background(current, index, digit),
      foreground(current, clashes, index, digit),
    ]
    |> list.filter(fn(style) { style != "" })
    |> string.join(";")

  term.styled(styles, " " <> text)
}

fn answer_column(text: String) -> String {
  string.pad_start(text, content_width, " ")
}

/// Marks that do not fit lose their tail to a `+`. The status line below the
/// board always spells out the cursor cell's marks in full, so nothing the
/// player wrote is ever out of reach.
fn mark_column(marks: List(Int)) -> String {
  let digits = list.map(marks, int.to_string)

  case list.length(digits) > content_width {
    False -> string.concat(digits)
    True -> string.concat(list.take(digits, content_width - 1)) <> "+"
  }
}

fn foreground(
  current: Game,
  clashes: Set(Int),
  index: Int,
  digit: Int,
) -> String {
  case
    digit == 0 && !set.is_empty(board.marks_at(current.board, index)),
    digit == 0,
    current.checking && game.is_wrong(current, index),
    set.contains(clashes, index),
    board.is_given(current.board, index)
  {
    True, _, _, _, _ -> mark_style
    _, True, _, _, _ -> empty_style
    _, _, True, _, _ -> wrong_style
    _, _, _, True, _ -> conflict_style
    _, _, _, _, True -> given_style
    _, _, _, _, _ -> entered_style
  }
}

fn background(current: Game, index: Int, digit: Int) -> String {
  let focus = board.value(current.board, current.cursor)

  case
    index == current.cursor,
    digit != 0 && digit == focus,
    shares_unit(index, current.cursor)
  {
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
// Everything below the grid
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

/// The cursor cell's marks, written out in full. This is where marks too
/// numerous to fit in the cell itself can still be read.
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
  #("c", "check what is filled in so far"),
  #("H", "reveal one cell"),
  #("R", "reveal the whole solution"),
  #("n", "start a new puzzle"),
  #("?", "close this help"),
  #("q", "quit"),
]

fn help() -> List(String) {
  let entries = {
    use #(keys, meaning) <- list.map(key_reference)
    "  "
    <> term.styled(entered_style, string.pad_end(keys, 22, " "))
    <> term.styled(dim_style, meaning)
  }

  list.flatten([
    [term.styled("1", "Keys"), ""],
    entries,
    [
      "",
      term.styled(
        dim_style,
        "Writing a digit rubs out that digit's marks in every cell it can see.",
      ),
      term.styled(dim_style, "Any key returns to the board."),
    ],
  ])
}

fn finished(current: Game) -> List(String) {
  let headline = case current.revealed {
    True -> term.styled(dim_style, "Solution revealed.")
    False ->
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
