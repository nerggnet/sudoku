//// A Sudoku game for the terminal.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sudoku/editor
import sudoku/game
import sudoku/generator.{type Difficulty, type Origin}
import sudoku/key
import sudoku/render
import sudoku/term

pub fn main() -> Nil {
  let raw = term.enable_raw()

  term.enter()
  run(raw)
  term.leave()

  io.println("Thanks for playing.")
}

fn run(raw: Bool) -> Nil {
  case choose_origin(raw) {
    None -> Nil
    Some(generator.Dealt(difficulty)) -> {
      term.write(generating(difficulty))
      start(raw, generator.generate(difficulty))
    }
    Some(generator.Handwritten) -> compose(raw, editor.new())
  }
}

/// Type a puzzle in, then play it. Anything the editor will not accept keeps
/// the editor up with a note about what is wrong, so the clues can be fixed
/// where they are.
fn compose(raw: Bool, current: editor.Editor) -> Nil {
  term.write(render.editor_frame(current))

  case editor.update(current, key.read()) {
    editor.Continue(next) -> compose(raw, next)
    editor.Ready(puzzle) -> start(raw, puzzle)
    editor.Cancel -> run(raw)
    editor.Exit -> Nil
  }
}

fn start(raw: Bool, puzzle: generator.Puzzle) -> Nil {
  case play(game.new(puzzle)) {
    game.Restart -> run(raw)
    _ -> Nil
  }
}

fn play(current: game.Game) -> game.Step {
  term.write(render.frame(current))

  case game.update(current, key.read()) {
    game.Continue(next) -> play(next)
    step -> step
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

fn choose_origin(raw: Bool) -> Option(Origin) {
  term.write(menu(raw))

  case key.read() {
    key.Quit | key.Char("q") | key.Char("Q") -> None
    key.Digit(picked) ->
      case list.drop(choices(), picked - 1) {
        [origin, ..] -> Some(origin)
        [] -> choose_origin(raw)
      }
    _ -> choose_origin(raw)
  }
}

fn menu(raw: Bool) -> String {
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
      ["", "   " <> term.styled("96", "q") <> "  quit"],
      note,
    ]),
  )
}

/// What each menu entry gets you: a clue count for a dealt puzzle, and for a
/// custom one, a grid to type a puzzle of your own into.
fn aside(origin: Origin) -> String {
  case origin {
    generator.Dealt(difficulty) ->
      int.to_string(generator.target_clues(difficulty)) <> " clues"
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
