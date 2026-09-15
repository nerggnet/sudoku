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
import gleam/option.{Some}
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
    clock_field <> int.to_string(game.elapsed_ms(current)),
    "checking " <> yes_no(current.checking),
    "aided " <> yes_no(current.aided),
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
      // Older files have no such line, so a game helped along is recognised
        // by what it was helped with.
        aided: dict.get(fields, "aided") == Ok("yes")
        || dict.get(fields, "checking") == Ok("yes")
        || whole_at(fields, "hints", 0) > 0,
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

/// What became of a game when it was put down.
pub type Kept {
  /// Written down, and where to find it again.
  PutDown(where: String)
  /// Nothing was written, and nothing needed to be: the game was over.
  NothingToKeep
  /// There was a game to keep and it could not be written. Worth saying: an
  /// hour of somebody's puzzle and a confident sentence about where it went
  /// is worse than no sentence at all.
  Lost(where: String)
}

/// The one line of the file that moves on its own.
const clock_field = "clock "

/// How far behind the file's clock is allowed to fall.
///
/// A game is written down when something happens to it, and nothing happens
/// while somebody sits and thinks. That thinking is time spent on the puzzle
/// all the same, so a file left at the last move would hand it back to
/// anybody whose terminal died — a way of stopping the clock without
/// pressing `p`, and the one thing a best time must not be open to. Half a
/// minute is what a crash can forgive.
const keep_within_ms = 30_000

/// What has been written down, so far as the game needs to know: enough to
/// tell whether writing it again would say anything worth saying.
pub type Written {
  /// Nothing yet, which is always worth writing.
  Unwritten
  Written(shape: String, clock: Int)
}

/// Mark this game as the one now written down.
pub fn written(current: Game) -> Written {
  Written(shape: shape(current), clock: game.elapsed_ms(current))
}

/// Whether the game has moved on from what is written down.
///
/// Two ways it can have. Something the file holds is different, which is
/// somebody having played; or the clock has run on far enough that the file
/// would give time back.
pub fn moved_on(current: Game, written: Written) -> Bool {
  case written {
    Unwritten -> True
    Written(shape: was, clock: then) ->
      shape(current) != was || game.elapsed_ms(current) - then > keep_within_ms
  }
}

/// What would be written down, apart from how long it has taken.
///
/// Compared as the text itself rather than as a list of fields to check, so
/// that a field added to the file cannot be left out of this by forgetting
/// to add it twice.
fn shape(current: Game) -> String {
  encode(current)
  |> string.split("\n")
  |> list.filter(fn(line) { !string.starts_with(line, clock_field) })
  |> string.join("\n")
}

/// Keep this game to come back to. A game already over is not kept: there is
/// nothing left to come back to.
pub fn keep(current: Game) -> Kept {
  case game.is_finished(current) {
    True -> {
      forget()
      NothingToKeep
    }
    False ->
      case write_file(game_file, encode(current)) {
        True -> PutDown(path())
        False -> Lost(path())
      }
  }
}

/// The game left behind last time, if there is one and it can still be read.
pub fn saved() -> Result(Game, Nil) {
  read_file(game_file) |> result.try(decode)
}

pub fn forget() -> Nil {
  forget_file(game_file)
}

/// Where a game is kept. Handed out with the answer about whether one landed
/// there, rather than on its own: a path is only worth printing alongside
/// what did or did not happen at it.
fn path() -> String {
  file_path(game_file)
}

const game_file = "game"

const bests_file = "bests"

@external(erlang, "sudoku_ffi", "file_path")
fn file_path(name: String) -> String

@external(erlang, "sudoku_ffi", "write_file")
fn write_file(name: String, text: String) -> Bool

@external(erlang, "sudoku_ffi", "read_file")
fn read_file(name: String) -> Result(String, Nil)

@external(erlang, "sudoku_ffi", "forget_file")
fn forget_file(name: String) -> Nil

// ---------------------------------------------------------------------------
// The record books
// ---------------------------------------------------------------------------

/// The quickest unaided solve at each difficulty, in milliseconds.
pub type Bests =
  Dict(generator.Difficulty, Int)

/// What the record books make of a finished game, writing the time down if it
/// belongs there.
///
/// This is the only moment the book is opened, which is why it is opened for
/// reading and writing at once.
pub fn settle(current: Game) -> game.Verdict {
  let books = bests()
  let verdict = judge(current, books)

  case verdict {
    // The books are only worth anything if the writing lands. A time nobody
    // can look up later is not a record, whatever the panel says.
    game.BestYet ->
      case write_bests(with_time(current, books)) {
        True -> game.BestYet
        False -> game.BestNotKept
      }
    _ -> verdict
  }
}

/// What the record books make of a game, given what they already hold. Kept
/// apart from the reading and writing so that it can be thought about, and
/// tested, on its own.
pub fn judge(current: Game, books: Bests) -> game.Verdict {
  case current.puzzle.origin, current.ending, game.unaided(current) {
    generator.Dealt(difficulty), Some(game.Solved), True ->
      case dict.get(books, difficulty) {
        Ok(best) ->
          case game.elapsed_ms(current) < best {
            True -> game.BestYet
            False -> game.Behind(best)
          }
        Error(_) -> game.BestYet
      }

    // Solved, but with the answer to hand one way or another.
    _, Some(game.Solved), False -> game.Aided

    // A puzzle typed in has no difficulty to file a time under, and a game
    // not won has no time to file.
    _, _, _ -> game.Untimed
  }
}

fn with_time(current: Game, books: Bests) -> Bests {
  case current.puzzle.origin {
    generator.Dealt(difficulty) ->
      dict.insert(books, difficulty, game.elapsed_ms(current))
    generator.Handwritten -> books
  }
}

/// The quickest unaided solve at each difficulty so far.
pub fn bests() -> Bests {
  let text = read_file(bests_file) |> result.unwrap("")

  use books, line <- list.fold(string.split(text, "\n"), dict.new())
  case string.split_once(string.trim(line), " ") {
    Error(_) -> books
    Ok(#(name, taken)) ->
      case generator.named(name), int.parse(string.trim(taken)) {
        Ok(difficulty), Ok(milliseconds) ->
          dict.insert(books, difficulty, milliseconds)
        _, _ -> books
      }
  }
}

fn write_bests(books: Bests) -> Bool {
  let lines = {
    use difficulty <- list.filter_map(generator.difficulties)
    case dict.get(books, difficulty) {
      Error(_) -> Error(Nil)
      Ok(taken) ->
        Ok(
          string.lowercase(generator.label(difficulty))
          <> " "
          <> int.to_string(taken),
        )
    }
  }

  write_file(bests_file, string.join(lines, "\n"))
}

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
