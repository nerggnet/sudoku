//// Putting a game down and picking it up again.
////
//// A game is written out as a few lines of text, one thing to a line, so
//// that the file can be read by a person as well as by this. Everything that
//// cannot be worked out again is in it: the clues, the answer, what has been
//// written and pencilled in since, and what the game has cost so far.
////
//// The undo history is not. It is the longest thing in a game by far and the
//// least missed, and a puzzle picked up tomorrow is not one anybody wants to
//// walk backwards through.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import sudoku/board.{type Board, type Grid}
import sudoku/game.{type Game}
import sudoku/generator.{type Origin}
import sudoku/term

/// The format, so that a file from an older game can be told apart from one
/// this cannot read.
const version = "sudoku 1"

// ---------------------------------------------------------------------------
// Writing a game out and reading it back
// ---------------------------------------------------------------------------

pub fn encode(current: Game) -> String {
  [
    version,
    "origin " <> named(current.puzzle.origin),
    "clues " <> board.to_string(current.puzzle.board.values),
    "answer " <> board.to_string(current.puzzle.solution),
    "board " <> board.to_string(current.board.values),
    "marks " <> pencilled(current.board),
    "cursor " <> int.to_string(current.cursor),
    "clock " <> int.to_string(game.elapsed_ms(current)),
    "checking " <> yes_no(current.checking),
    "wrong " <> int.to_string(current.mistakes),
    "hints " <> int.to_string(current.hints),
  ]
  |> string.join("\n")
}

/// Read a game back, or refuse the file.
///
/// A file that has been edited by hand, or written by another version, or
/// half written by a machine that went down in the middle, is no use here. It
/// is checked as far as it can be — the answer really is an answer, and the
/// clues really are its clues — and anything that fails is simply not a saved
/// game.
pub fn decode(text: String) -> Result(Game, Nil) {
  let fields = {
    use fields, line <- list.fold(string.split(text, "\n"), dict.new())
    case string.split_once(string.trim(line), " ") {
      Ok(#(key, value)) -> dict.insert(fields, key, string.trim(value))
      Error(_) -> fields
    }
  }

  use _ <- result.try(case string.starts_with(text, version) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })

  use clues <- result.try(grid_at(fields, "clues"))
  use answer <- result.try(grid_at(fields, "answer"))
  use values <- result.try(grid_at(fields, "board"))
  use origin <- result.try(
    dict.get(fields, "origin") |> result.try(origin_named),
  )
  use _ <- result.try(check(clues, answer, values))

  let puzzle =
    generator.Puzzle(
      board: board.from_grid(clues),
      solution: answer,
      origin: origin,
    )
  let started = game.new(puzzle)

  Ok(
    game.Game(
      ..started,
      board: board.Board(
        values: values,
        givens: started.board.givens,
        marks: marks_at(fields),
      ),
      cursor: whole_at(fields, "cursor", started.cursor),
      checking: dict.get(fields, "checking") == Ok("yes"),
      mistakes: whole_at(fields, "wrong", 0),
      hints: whole_at(fields, "hints", 0),
      started_ms: term.now_ms() - whole_at(fields, "clock", 0),
      message: "Picked up where you left off.",
    ),
  )
}

/// What the file has to hold together on: an answer that is one, clues that
/// are its clues, and nothing written in that contradicts them.
fn check(clues: Grid, answer: Grid, values: Grid) -> Result(Nil, Nil) {
  let agrees = fn(grid: Grid, with: fn(Int, Int) -> Bool) {
    use index <- list.all(board.indices())
    case dict.get(grid, index) {
      Ok(0) | Error(_) -> True
      Ok(digit) -> with(index, digit)
    }
  }

  let same_as_answer = fn(index, digit) { dict.get(answer, index) == Ok(digit) }

  case
    board.is_solved(board.from_grid(answer)),
    agrees(clues, same_as_answer),
    agrees(clues, fn(index, digit) { dict.get(values, index) == Ok(digit) })
  {
    True, True, True -> Ok(Nil)
    _, _, _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// The file itself
// ---------------------------------------------------------------------------

/// Keep this game to come back to. A game already over is not kept: there is
/// nothing left to come back to.
pub fn keep(current: Game) -> Nil {
  case game.is_finished(current) {
    True -> forget()
    False -> {
      let _ = write_save(encode(current))
      Nil
    }
  }
}

/// The game left behind last time, if there is one and it can still be read.
pub fn saved() -> Result(Game, Nil) {
  read_save() |> result.try(decode)
}

@external(erlang, "sudoku_ffi", "forget_save")
pub fn forget() -> Nil

/// Where a game is kept, for the parting message to say.
@external(erlang, "sudoku_ffi", "save_path")
pub fn path() -> String

@external(erlang, "sudoku_ffi", "write_save")
fn write_save(text: String) -> Bool

@external(erlang, "sudoku_ffi", "read_save")
fn read_save() -> Result(String, Nil)

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

fn named(origin: Origin) -> String {
  string.lowercase(generator.origin_label(origin))
}

fn origin_named(name: String) -> Result(Origin, Nil) {
  case name == named(generator.Handwritten) {
    True -> Ok(generator.Handwritten)
    False -> generator.named(name) |> result.map(generator.Dealt)
  }
}

fn grid_at(fields: Dict(String, String), key: String) -> Result(Grid, Nil) {
  dict.get(fields, key) |> result.try(board.parse)
}

fn whole_at(fields: Dict(String, String), key: String, or: Int) -> Int {
  dict.get(fields, key) |> result.try(int.parse) |> result.unwrap(or)
}

/// Marks as `cell:digits`, only for the cells that have any: `2:1478 9:35`.
fn pencilled(current: Board) -> String {
  board.indices()
  |> list.filter_map(fn(index) {
    case board.sorted_marks(current, index) {
      [] -> Error(Nil)
      marks ->
        Ok(
          int.to_string(index)
          <> ":"
          <> string.concat(list.map(marks, int.to_string)),
        )
    }
  })
  |> string.join(" ")
}

fn marks_at(fields: Dict(String, String)) -> Dict(Int, set.Set(Int)) {
  let written = dict.get(fields, "marks") |> result.unwrap("")

  use marks, entry <- list.fold(string.split(written, " "), dict.new())
  case string.split_once(entry, ":") {
    Error(_) -> marks
    Ok(#(where, digits)) ->
      case int.parse(where) {
        Error(_) -> marks
        Ok(index) ->
          case digits_of(digits) {
            [] -> marks
            digits -> dict.insert(marks, index, set.from_list(digits))
          }
      }
  }
}

fn digits_of(text: String) -> List(Int) {
  use character <- list.filter_map(string.to_graphemes(text))
  case int.parse(character) {
    Ok(digit) if digit > 0 -> Ok(digit)
    _ -> Error(Nil)
  }
}

fn yes_no(yes: Bool) -> String {
  case yes {
    True -> "yes"
    False -> "no"
  }
}
