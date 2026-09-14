//// Typing a puzzle in by hand.
////
//// This is how a puzzle out of a newspaper gets played: the clues are typed
//// into an empty grid, and once they have exactly one answer between them the
//// game starts as if they had been dealt.
////
//// The cursor steps on by itself after every digit, so a row is nine
//// keystrokes and the whole grid is eighty-one, read straight off the page.

import gleam/dict
import gleam/list
import sudoku/board.{type Grid}
import sudoku/generator.{type Puzzle}
import sudoku/key.{type Key}

const max_undo = 200

pub type Editor {
  Editor(
    clues: Grid,
    cursor: Int,
    history: List(Grid),
    message: String,
    show_help: Bool,
  )
}

/// What the main loop should do after handling a key.
pub type Step {
  Continue(Editor)
  /// The clues have one answer between them, so they can be played.
  Ready(Puzzle)
  /// Back to the opening menu.
  Cancel
  Exit
}

pub fn new() -> Editor {
  Editor(
    clues: board.empty_grid(),
    cursor: 0,
    history: [],
    message: "Type the puzzle in row by row. Press ? for help.",
    show_help: False,
  )
}

pub fn value(current: Editor, index: Int) -> Int {
  case dict.get(current.clues, index) {
    Ok(digit) -> digit
    Error(_) -> 0
  }
}

pub fn clue_count(current: Editor) -> Int {
  current.clues |> dict.values |> list.count(fn(digit) { digit != 0 })
}

pub fn update(current: Editor, pressed: Key) -> Step {
  case pressed {
    // Line mode sends a newline after every key, which the player did not
    // press. Left to count as a keystroke it would close the help the moment
    // it opened.
    key.Unknown -> Continue(current)

    key.Quit | key.Char("q") | key.Char("Q") -> Exit
    key.Char("?") -> Continue(Editor(..current, show_help: !current.show_help))

    // While the help overlay is up, any other key dismisses it.
    _ if current.show_help -> Continue(Editor(..current, show_help: False))

    key.Char("n") | key.Char("N") -> Cancel

    key.Up | key.Char("k") | key.Char("w") -> Continue(move(current, -1, 0))
    key.Down | key.Char("j") | key.Char("s") -> Continue(move(current, 1, 0))
    key.Left | key.Char("h") | key.Char("a") -> Continue(move(current, 0, -1))
    key.Right | key.Char("l") | key.Char("d") -> Continue(move(current, 0, 1))

    key.Digit(digit) | key.Shifted(digit) -> Continue(type_in(current, digit))
    key.Erase -> Continue(type_in(current, 0))

    key.Char("u") -> Continue(undo(current))
    key.Char("x") | key.Char("X") -> Continue(clear(current))
    key.Char("p") | key.Char("P") -> finish(current)

    _ -> Continue(current)
  }
}

fn move(current: Editor, rows: Int, cols: Int) -> Editor {
  let row = { board.row_of(current.cursor) + rows + board.side } % board.side
  let col = { board.col_of(current.cursor) + cols + board.side } % board.side
  Editor(..current, cursor: board.at(row, col), message: "")
}

/// Write a digit into the cell and step on to the next one in reading order,
/// which is the order a puzzle is read off the page. `0` leaves a gap.
///
/// Clues that clash are allowed to stand rather than being refused: while a
/// row is half typed in, a digit may well clash with one that is about to be
/// corrected. They show up red, and `p` will not start a game on them.
fn type_in(current: Editor, digit: Int) -> Editor {
  let written = case value(current, current.cursor) == digit {
    True -> current
    False ->
      Editor(
        ..remember(current),
        clues: dict.insert(current.clues, current.cursor, digit),
      )
  }

  Editor(
    ..written,
    cursor: { current.cursor + 1 } % board.cell_count,
    message: "",
  )
}

fn undo(current: Editor) -> Editor {
  case current.history {
    [] -> Editor(..current, message: "Nothing left to undo.")
    [previous, ..rest] ->
      Editor(..current, clues: previous, history: rest, message: "Undone.")
  }
}

fn clear(current: Editor) -> Editor {
  case clue_count(current) {
    0 -> Editor(..current, message: "The grid is already empty.")
    _ ->
      Editor(
        ..remember(current),
        clues: board.empty_grid(),
        cursor: 0,
        message: "Cleared. Starting again from A1.",
      )
  }
}

/// Hand the clues over to be played, if they hold together.
fn finish(current: Editor) -> Step {
  case clue_count(current) {
    0 -> Continue(Editor(..current, message: "Type the clues in first."))
    _ ->
      case generator.from_clues(current.clues) {
        Ok(puzzle) -> Ready(puzzle)
        Error(rejection) ->
          Continue(Editor(..current, message: refusal(rejection)))
      }
  }
}

/// What to say about clues that cannot be played, and what to do about it.
pub fn refusal(rejection: generator.Rejection) -> String {
  case rejection {
    generator.Clashes ->
      "Two of the same digit share a row, column or box: the red ones clash."
    generator.Unsolvable ->
      "These clues have no answer, so one of them must be mistyped."
    generator.Ambiguous ->
      "These clues have more than one answer, so one must be missing."
  }
}

fn remember(current: Editor) -> Editor {
  Editor(
    ..current,
    history: list.take([current.clues, ..current.history], max_undo),
  )
}
