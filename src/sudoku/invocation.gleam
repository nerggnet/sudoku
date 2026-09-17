//// What the words the game was started with are asking for.
////
//// Kept apart from acting on them. Reading a command line is a question
//// about text — is that a difficulty, a puzzle, a flag, or nonsense? — and
//// answering it needs no terminal, no saved game and no puzzle dealt. Doing
//// something about the answer needs all three, and is next door in the main
//// module.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sudoku/board
import sudoku/date.{type Date}
import sudoku/editor
import sudoku/generator.{type Difficulty, type Puzzle}
import sudoku/help

/// What was asked for.
pub type Asked {
  /// Nothing, so the menu decides.
  Menu
  /// A puzzle dealt at this difficulty.
  Deal(difficulty: Difficulty)
  /// A grid to type a puzzle into.
  Compose
  /// The game left behind last time, if there is one left behind.
  Resume
  /// The puzzle belonging to today, whichever day that turns out to be.
  ///
  /// Kept as "today" rather than read into a date here, since reading a
  /// command line is meant to need nothing of the world — and what day it is
  /// is the most worldly thing there is. The main module asks the clock.
  Today
  /// The puzzle belonging to a day that was named outright.
  Day(on: Date)
  /// This puzzle, given as its 81 characters.
  Play(puzzle: Puzzle)
  /// Nothing to play: what the command line takes, which is a question
  /// about the game rather than a game.
  Explain
}

/// That, and how the game should look while it does it, and which deal to
/// deal where it was asked for a particular one.
pub type Invocation {
  Invocation(asked: Asked, plain: Bool, seed: Option(Int))
}

/// The flags there are. Everything else on the command line names a puzzle.
pub const plain_flag = "--plain"

/// Both spellings of asking what any of this takes.
pub const help_flags = ["--help", "-h"]

/// Asking for one deal in particular rather than whichever one comes up.
pub const seed_flag = "--seed"

/// Asking for the puzzle that belongs to a day.
pub const daily_word = "daily"

/// Read a command line, or refuse it with something worth reading.
///
/// Flags are taken out first, and what is left over is read as though they
/// had never been there — so each of them can sit on either side of the
/// puzzle, wherever it fell out of the hand that typed it.
///
/// Only one of them has anything to say about what is dealt, and it is the
/// one that has to be taken out most carefully: `--seed` carries a word of
/// its own, and that word would otherwise be read as a puzzle and refused
/// for not being one.
pub fn read(arguments: List(String)) -> Result(Invocation, String) {
  // Asked for outright, and answered before anything else is read. Somebody
  // who types --help wants to be told what the words mean, and nothing else
  // on the line can turn that into a mistake — not a puzzle beside it, not
  // another flag that would have been one on its own, and not a seed that
  // is not a number.
  case list.any(arguments, fn(word) { list.contains(help_flags, word) }) {
    True -> Ok(Invocation(Explain, list.contains(arguments, plain_flag), None))
    False -> {
      // Taken out before the rest is picked apart, since a seed is the one
      // flag that carries a word of its own and that word is not a puzzle.
      use #(seed, arguments) <- result.try(seed_taken_from(arguments))

      let #(flags, rest) = list.partition(arguments, string.starts_with(_, "-"))
      played(flags, rest, list.contains(flags, plain_flag), seed)
    }
  }
}

/// Take the seed out of the line, and hand back what is left of it.
///
/// Written either way round, `--seed 42` or `--seed=42`, because both are
/// what people type and neither is worth being told off for.
fn seed_taken_from(
  arguments: List(String),
) -> Result(#(Option(Int), List(String)), String) {
  use #(seeds, rest) <- result.try(scan(arguments, [], []))

  case seeds {
    [] -> Ok(#(None, rest))
    [only] -> Ok(#(Some(only), rest))
    // Two seeds are two deals, and only one of them can be dealt. Which is
    // not a thing to guess at on somebody's behalf.
    [_, _, ..] ->
      Error("Only one " <> seed_flag <> " can be given, and there are two.")
  }
}

fn scan(
  arguments: List(String),
  seeds: List(Int),
  rest: List(String),
) -> Result(#(List(Int), List(String)), String) {
  case arguments {
    [] -> Ok(#(list.reverse(seeds), list.reverse(rest)))
    [word, ..more] ->
      case string.split_once(word, "="), word == seed_flag, more {
        // `--seed=42`, the number carried in the word itself.
        Ok(#(flag, value)), _, _ if flag == seed_flag ->
          taken(value, more, seeds, rest)
        // `--seed 42`, the number in the word after it.
        _, True, [value, ..after] -> taken(value, after, seeds, rest)
        _, True, [] -> Error(seed_flag <> " wants a whole number after it.")
        _, _, _ -> scan(more, seeds, [word, ..rest])
      }
  }
}

fn taken(
  value: String,
  more: List(String),
  seeds: List(Int),
  rest: List(String),
) -> Result(#(List(Int), List(String)), String) {
  case int.parse(value) {
    Ok(seed) -> scan(more, [seed, ..seeds], rest)
    // Including the case where the next word was another flag, which is
    // somebody who left the number out: the complaint names what was found
    // in its place rather than saying only that something is missing.
    Error(_) -> Error("A seed is a whole number, and " <> value <> " is not.")
  }
}

/// What the line asks to be played, once it is known that it asks for that
/// rather than for an explanation.
fn played(
  flags: List(String),
  rest: List(String),
  plain: Bool,
  seed: Option(Int),
) -> Result(Invocation, String) {
  use _ <- result.try(case list.all(flags, fn(flag) { flag == plain_flag }) {
    True -> Ok(Nil)
    False -> Error(help.usage())
  })

  use asked <- result.try(case rest {
    [] -> Ok(Menu)
    [only] -> asked(only)
    // The one thing on the line that takes a word of its own, a date being
    // no use to anybody as a bare word: `.` and digits would read as a
    // puzzle, and 2026-09-17 as nothing at all.
    [first, on] -> dated(first, on)
    _ -> Error(help.usage())
  })

  use _ <- result.try(seed_has_a_deal(asked, seed))
  Ok(Invocation(asked, plain, seed))
}

/// A seed names a deal, so there has to be a deal on the line for it to
/// name.
///
/// Refused rather than quietly let by. Somebody who types `--seed 42 custom`
/// believes something about what is coming, and what is coming is a grid
/// they type in themselves — which the seed had no hand in, and would go on
/// having no hand in while they wondered why.
fn seed_has_a_deal(asked: Asked, seed: Option(Int)) -> Result(Nil, String) {
  case asked, seed {
    _, None -> Ok(Nil)
    Deal(_), Some(_) -> Ok(Nil)
    // A daily has its seed already, and it is the day: that is the whole of
    // why everybody asking for a day is handed the same grid. A second one
    // beside it would have to be ignored, and ignoring it quietly is how
    // somebody comes to believe they are playing a puzzle they are not.
    Today, Some(_) | Day(_), Some(_) ->
      Error(
        "A daily puzzle is carved from its own date, so "
        <> seed_flag
        <> " has nothing to add to it.",
      )
    _, Some(_) ->
      Error(
        seed_flag
        <> " deals one puzzle again, so it wants a difficulty to deal:"
        <> "\n  gleam run -- hard "
        <> seed_flag
        <> " 42",
      )
  }
}

/// `daily 2026-09-17`, which is the day named rather than taken from the
/// clock. What two people in different places use when they want the same
/// grid and their calendars have already disagreed about what day it is.
fn dated(first: String, on: String) -> Result(Asked, String) {
  case string.lowercase(first) == daily_word {
    False -> Error(help.usage())
    True ->
      case date.parse(on) {
        Ok(on) -> Ok(Day(on))
        Error(_) ->
          Error(
            "A day is written like 2026-09-17, and "
            <> on
            <> " is not — or is not a day that happened.",
          )
      }
  }
}

fn asked(argument: String) -> Result(Asked, String) {
  case string.lowercase(argument) {
    "resume" -> Ok(Resume)
    "custom" -> Ok(Compose)
    name if name == daily_word -> Ok(Today)
    name ->
      case generator.named(name) {
        Ok(difficulty) -> Ok(Deal(difficulty))
        Error(_) -> typed_in(argument)
      }
  }
}

/// A puzzle given as its 81 characters, the same line the game prints on the
/// way out and the editor takes.
///
/// Anything that is not 81 characters was meant to be a word rather than a
/// puzzle, so it gets the usage rather than a complaint about its clues.
fn typed_in(argument: String) -> Result(Asked, String) {
  case board.parse(argument) {
    Error(_) -> Error(help.usage())
    Ok(clues) ->
      case generator.from_clues(clues) {
        Ok(puzzle) -> Ok(Play(puzzle))
        Error(rejection) -> Error(editor.refusal(rejection))
      }
  }
}
