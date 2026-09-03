//// A Sudoku game for the terminal.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sudoku/game
import sudoku/generator.{type Difficulty}
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
  case choose_difficulty(raw) {
    None -> Nil
    Some(difficulty) -> {
      term.write(generating(difficulty))
      let started = game.new(generator.generate(difficulty))

      case play(started) {
        game.Restart -> run(raw)
        _ -> Nil
      }
    }
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
// Difficulty menu
// ---------------------------------------------------------------------------

fn choose_difficulty(raw: Bool) -> Option(Difficulty) {
  term.write(menu(raw))

  case key.read() {
    key.Quit | key.Char("q") | key.Char("Q") -> None
    key.Digit(picked) ->
      case list.drop(generator.difficulties, picked - 1) {
        [difficulty, ..] -> Some(difficulty)
        [] -> choose_difficulty(raw)
      }
    _ -> choose_difficulty(raw)
  }
}

fn menu(raw: Bool) -> String {
  let options = {
    use difficulty, index <- list.index_map(generator.difficulties)
    "   "
    <> term.styled("96", int.to_string(index + 1))
    <> "  "
    <> string.pad_end(generator.label(difficulty), 10, " ")
    <> term.styled(
      "90",
      int.to_string(generator.target_clues(difficulty)) <> " clues",
    )
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
      [term.styled("1;95", "S U D O K U"), "", "Choose a difficulty:", ""],
      options,
      ["", "   " <> term.styled("96", "q") <> "  quit"],
      note,
    ]),
  )
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
