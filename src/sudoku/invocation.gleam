//// What the words the game was started with are asking for.
////
//// Kept apart from acting on them. Reading a command line is a question
//// about text — is that a difficulty, a puzzle, a flag, or nonsense? — and
//// answering it needs no terminal, no saved game and no puzzle dealt. Doing
//// something about the answer needs all three, and is next door in the main
//// module.

import gleam/list
import gleam/result
import gleam/string
import sudoku/board
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
  /// This puzzle, given as its 81 characters.
  Play(puzzle: Puzzle)
}

/// That, and how the game should look while it does it.
pub type Invocation {
  Invocation(asked: Asked, plain: Bool)
}

/// The one flag there is. Everything else on the command line names a puzzle.
pub const plain_flag = "--plain"

/// Read a command line, or refuse it with something worth reading.
///
/// Flags are taken out first. They say how the game should look rather than
/// what it should deal, so they can come before or after a puzzle, and what
/// is left over is read as though they had never been there.
pub fn read(arguments: List(String)) -> Result(Invocation, String) {
  let #(flags, rest) = list.partition(arguments, string.starts_with(_, "-"))

  use _ <- result.try(case list.all(flags, fn(flag) { flag == plain_flag }) {
    True -> Ok(Nil)
    False -> Error(help.usage())
  })

  let plain = list.contains(flags, plain_flag)

  case rest {
    [] -> Ok(Invocation(Menu, plain))
    [only] -> asked(only) |> result.map(Invocation(_, plain))
    _ -> Error(help.usage())
  }
}

fn asked(argument: String) -> Result(Asked, String) {
  case string.lowercase(argument) {
    "resume" -> Ok(Resume)
    "custom" -> Ok(Compose)
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
