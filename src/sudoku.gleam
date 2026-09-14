//// A Sudoku game for the terminal.

import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator.{type Difficulty, type Origin}
import sudoku/help
import sudoku/key
import sudoku/render
import sudoku/rules
import sudoku/store
import sudoku/term

pub fn main() -> Nil {
  case asked_for(term.arguments()) {
    // Said before the screen is taken over, where it can be read afterwards.
    Error(complaint) -> io.println(complaint)
    Ok(Opening(opening, plain)) -> {
      // Only ever switched on here: without the flag the environment has the
      // say, and NO_COLOR is not something to talk anybody out of.
      case plain {
        True -> term.plainly(True)
        False -> Nil
      }

      let raw = term.enable_raw()

      term.enter()
      let played = case opening {
        None -> run(raw)
        Some(chosen) -> follow(raw, chosen)
      }
      term.leave()

      io.println("Thanks for playing.")
      parting(played)
    }
  }
}

/// What the command line asked for: a puzzle to open with, where it named
/// one, and how the game should be drawn.
type Opening {
  Opening(choice: Option(Choice), plain: Bool)
}

/// The one flag there is. Everything else on the command line names a puzzle.
const plain_flag = "--plain"

/// What the command line asks for: nothing, and the menu decides; something,
/// and it is gone to straight away; or nonsense, which is said plainly and
/// stops there.
///
/// Flags are taken out first. They say how the game should look rather than
/// what it should deal, so they can come before or after the puzzle, and what
/// is left over is read as though they had never been there.
fn asked_for(arguments: List(String)) -> Result(Opening, String) {
  let #(flags, rest) = list.partition(arguments, string.starts_with(_, "-"))

  use _ <- result.try(case list.all(flags, fn(flag) { flag == plain_flag }) {
    True -> Ok(Nil)
    False -> Error(help.usage())
  })

  let plain = list.contains(flags, plain_flag)

  case rest {
    [] -> Ok(Opening(None, plain))
    [only] ->
      asked(only) |> result.map(fn(choice) { Opening(Some(choice), plain) })
    _ -> Error(help.usage())
  }
}

fn asked(argument: String) -> Result(Choice, String) {
  case string.lowercase(argument) {
    "resume" ->
      case store.saved() {
        Ok(current) -> Ok(Resume(current))
        Error(_) -> Error("There is no game waiting to be picked up.")
      }
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
fn typed_in(argument: String) -> Result(Choice, String) {
  case board.parse(argument) {
    Error(_) -> Error(help.usage())
    Ok(clues) ->
      case generator.from_clues(clues) {
        Ok(puzzle) -> Ok(Play(puzzle))
        Error(rejection) -> Error(editor.refusal(rejection))
      }
  }
}

/// Put the game down and say what happened to it: where it went, or that it
/// did not go anywhere, and then the puzzle itself, which is a line of text
/// anybody can type into Custom and play for themselves.
///
/// Saving happens here rather than as the game ends, so that what is written
/// down and what is said about it cannot come apart.
fn parting(played: Option(game.Game)) -> Nil {
  use current <- option_each(played)

  case store.keep(current) {
    store.NothingToKeep -> Nil
    store.PutDown(where) -> io.println("\nSaved in " <> where)
    store.Lost(where) -> io.println("\nCould not save in " <> where <> ".")
  }

  io.println("\nThis puzzle:")
  io.println(board.to_string(current.puzzle.board.values))
}

fn option_each(value: Option(a), run: fn(a) -> Nil) -> Nil {
  case value {
    Some(value) -> run(value)
    None -> Nil
  }
}

/// Read a key, drawing the screen again for as long as that is what is
/// asked for.
///
/// Every screen is drawn the same way, so this can answer Ctrl-L wherever it
/// is pressed without any of them knowing about it. Wiping first is the point
/// of it: an ordinary frame clears each line as it lands, which is no use
/// against a mess made by something other than the game.
fn press(frame: String) -> key.Key {
  case key.read() {
    key.Redraw -> {
      term.write(term.blank <> frame)
      press(frame)
    }
    pressed -> pressed
  }
}

/// What the opening menu offers, and what the command line can ask for
/// instead. Only the command line asks to play a particular puzzle.
type Choice {
  Deal(Difficulty)
  Compose
  Resume(game.Game)
  Play(generator.Puzzle)
  Stop
}

fn run(raw: Bool) -> Option(game.Game) {
  follow(raw, choose(raw, store.saved()))
}

fn follow(raw: Bool, chosen: Choice) -> Option(game.Game) {
  case chosen {
    Stop -> None
    Resume(current) -> start(raw, current)
    Play(puzzle) -> start(raw, game.new(puzzle))
    Compose -> compose(raw, editor.new())
    Deal(difficulty) -> {
      term.write(generating(difficulty))
      start(raw, game.new(generator.generate(difficulty)))
    }
  }
}

/// Type a puzzle in, then play it. Anything the editor will not accept keeps
/// the editor up with a note about what is wrong, so the clues can be fixed
/// where they are.
fn compose(raw: Bool, current: editor.Editor) -> Option(game.Game) {
  let frame = render.editor_frame(current)
  term.write(frame)

  case editor.update(current, press(frame)) {
    editor.Continue(next) -> compose(raw, next)
    editor.Ready(puzzle) -> start(raw, game.new(puzzle))
    editor.Cancel -> run(raw)
    editor.Exit -> None
  }
}

fn start(raw: Bool, current: game.Game) -> Option(game.Game) {
  let #(step, ended) = play(current)

  case step {
    // Asking for another puzzle abandons this one rather than putting it
    // down, so there is nothing to come back to.
    game.Restart -> {
      store.forget()
      run(raw)
    }
    // Not kept here: the parting message does that, so that the saving and
    // the sentence about it are one thing.
    _ -> Some(ended)
  }
}

fn play(current: game.Game) -> #(game.Step, game.Game) {
  let frame = render.frame(current)
  term.write(frame)

  case rules.update(current, press(frame)) {
    game.Continue(next) -> play(judged(current, next))
    step -> #(step, current)
  }
}

/// The moment a puzzle is solved is the moment to see what the record books
/// make of it, and the only moment they are opened.
fn judged(before: game.Game, after: game.Game) -> game.Game {
  case game.is_finished(before), game.is_finished(after) {
    False, True -> game.Game(..after, verdict: Some(store.settle(after)))
    _, _ -> after
  }
}

// ---------------------------------------------------------------------------
// Opening menu
// ---------------------------------------------------------------------------

/// What the menu offers: a puzzle dealt at each difficulty, and last of all
/// one typed in by hand.
fn choices() -> List(Origin) {
  generator.difficulties
  |> list.map(generator.Dealt)
  |> list.append([generator.Handwritten])
}

fn choose(raw: Bool, saved: Result(game.Game, Nil)) -> Choice {
  let frame = menu(raw, saved, store.bests())
  term.write(frame)

  case press(frame), saved {
    key.Quit, _ | key.Char("q"), _ | key.Char("Q"), _ -> Stop
    key.Char("r"), Ok(current) | key.Char("R"), Ok(current) -> Resume(current)
    key.Digit(picked), _ ->
      case list.drop(choices(), picked - 1) {
        [generator.Dealt(difficulty), ..] -> Deal(difficulty)
        [generator.Handwritten, ..] -> Compose
        [] -> choose(raw, saved)
      }
    _, _ -> choose(raw, saved)
  }
}

/// The game left behind last time, said in a line: what it was, how much of
/// it is left, and how long it took to get that far.
fn summary(current: game.Game) -> String {
  generator.origin_label(current.puzzle.origin)
  <> ", "
  <> int.to_string(board.empty_count(current.board))
  <> " to go, "
  <> render.clock(game.elapsed_ms(current))
}

fn menu(
  raw: Bool,
  saved: Result(game.Game, Nil),
  bests: store.Bests,
) -> String {
  let options = {
    use origin, index <- list.index_map(choices())
    "   "
    <> term.styled("96", int.to_string(index + 1))
    <> "  "
    <> string.pad_end(generator.origin_label(origin), 10, " ")
    <> term.styled("90", string.pad_end(aside(origin), 24, " "))
    <> term.styled("92", best(origin, bests))
  }

  let room = case render.cramped() {
    "" -> []
    complaint -> ["", term.styled("93", complaint)]
  }

  let note = case raw {
    True -> []
    False -> [
      "",
      term.styled(
        "93",
        "This terminal is in line mode: press Enter after each key.",
      ),
    ]
  }

  term.screen(
    list.flatten([
      [term.styled("1;95", "S U D O K U"), "", "Choose a puzzle:", ""],
      options,
      [
        "",
        "   "
          <> term.styled(
          "90",
          "Each level names the hardest reasoning its puzzles ask for.",
        ),
      ],
      case saved {
        Error(_) -> []
        Ok(current) -> [
          "",
          "   "
            <> term.styled("96", "r")
            <> "  "
            <> string.pad_end("Resume", 10, " ")
            <> term.styled("90", summary(current)),
        ]
      },
      ["", "   " <> term.styled("96", "q") <> "  quit"],
      room,
      note,
    ]),
  )
}

/// What each menu entry gets you: for a dealt puzzle, the hardest reasoning
/// it will ask of you, and for a custom one, a grid to type a puzzle of your
/// own into.
fn aside(origin: Origin) -> String {
  case origin {
    generator.Dealt(difficulty) -> generator.asks_for(difficulty)
    generator.Handwritten -> "type in a puzzle from a newspaper"
  }
}

/// The time to beat at this difficulty, where there is one. A puzzle typed
/// in has no difficulty to have a best at.
fn best(origin: Origin, bests: store.Bests) -> String {
  case origin {
    generator.Handwritten -> ""
    generator.Dealt(difficulty) ->
      case dict.get(bests, difficulty) {
        Error(_) -> ""
        Ok(taken) -> "best " <> render.clock(taken)
      }
  }
}

fn generating(difficulty: Difficulty) -> String {
  term.screen([
    term.styled("1;95", "S U D O K U"),
    "",
    term.styled(
      "90",
      "Carving out a " <> generator.label(difficulty) <> " puzzle...",
    ),
  ])
}
