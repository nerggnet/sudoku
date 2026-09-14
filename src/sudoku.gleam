//// A Sudoku game for the terminal.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator.{type Difficulty, type Origin}
import sudoku/key
import sudoku/render
import sudoku/store
import sudoku/term

pub fn main() -> Nil {
  let raw = term.enable_raw()

  term.enter()
  let played = run(raw)
  term.leave()

  io.println("Thanks for playing.")
  parting(played)
}

/// What to say once the screen has been handed back: where an unfinished game
/// went, and the puzzle itself, which is a line of text anybody can type into
/// Custom and play for themselves.
fn parting(played: Option(game.Game)) -> Nil {
  use current <- option_each(played)

  case game.is_finished(current) {
    True -> Nil
    False -> io.println("\nSaved in " <> store.path())
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

/// What the opening menu offers.
type Choice {
  Deal(Difficulty)
  Compose
  Resume(game.Game)
  Stop
}

fn run(raw: Bool) -> Option(game.Game) {
  case choose(raw, store.saved()) {
    Stop -> None
    Resume(current) -> start(raw, current)
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
  term.write(render.editor_frame(current))

  case editor.update(current, key.read()) {
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
    _ -> {
      store.keep(ended)
      Some(ended)
    }
  }
}

fn play(current: game.Game) -> #(game.Step, game.Game) {
  term.write(render.frame(current))

  case game.update(current, key.read()) {
    game.Continue(next) -> play(next)
    step -> #(step, current)
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
  term.write(menu(raw, saved))

  case key.read(), saved {
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

fn menu(raw: Bool, saved: Result(game.Game, Nil)) -> String {
  let options = {
    use origin, index <- list.index_map(choices())
    "   "
    <> term.styled("96", int.to_string(index + 1))
    <> "  "
    <> string.pad_end(generator.origin_label(origin), 10, " ")
    <> term.styled("90", aside(origin))
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
