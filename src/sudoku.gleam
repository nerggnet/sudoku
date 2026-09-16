//// A Sudoku game for the terminal.

import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator.{type Difficulty}
import sudoku/help
import sudoku/invocation
import sudoku/key
import sudoku/practice
import sudoku/render
import sudoku/rules
import sudoku/store
import sudoku/term

pub fn main() -> Nil {
  case opening(term.arguments()) {
    // Both said before the screen is taken over, where they can be read
    // afterwards. A question answered goes out the ordinary way; a command
    // line that could not be read goes out the way a shell can notice,
    // which is what a script piping this about has to go on.
    Say(said, True) -> io.println(said)
    Say(said, False) -> {
      io.println_error(said)
      term.stop(1)
    }

    Start(opening, plain) -> {
      // Only ever switched on here: without the flag the environment has the
      // say, and NO_COLOR is not something to talk anybody out of.
      case plain {
        True -> term.plainly(True)
        False -> Nil
      }

      let raw = term.enable_raw()

      let played = {
        use <- term.taking_over
        case opening {
          None -> run(raw)
          Some(chosen) -> follow(raw, chosen)
        }
      }

      io.println("Thanks for playing.")
      parting(played)
    }
  }
}

/// What the words the game was started with leave it to do.
type Opening {
  /// Play: this, or the menu where nothing was named.
  Start(chosen: Option(Choice), plain: Bool)
  /// Say this and stop, the screen never having been taken over. Whether it
  /// was asked for decides the way out: a question answered is not a
  /// failure, and a line nobody could read is not a success.
  Say(said: String, asked_for: Bool)
}

/// What the command line leaves the game to do, which is what it asked for
/// with the one thing added that reading words cannot settle: whether there
/// is in fact a game waiting to be picked up.
fn opening(arguments: List(String)) -> Opening {
  case invocation.read(arguments) {
    Error(complaint) -> Say(complaint, False)
    Ok(asked) ->
      case asked.asked {
        invocation.Explain -> Say(help.usage(), True)
        invocation.Menu -> Start(None, asked.plain)
        invocation.Compose -> Start(Some(Compose), asked.plain)
        invocation.Deal(difficulty) ->
          Start(Some(Deal(difficulty)), asked.plain)
        invocation.Play(puzzle) -> Start(Some(Play(puzzle)), asked.plain)
        invocation.Resume ->
          case store.saved() {
            Ok(current) -> Start(Some(Resume(current)), asked.plain)
            Error(_) -> Say("There is no game waiting to be picked up.", False)
          }
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

/// The same, for a screen that will not look the same for long: `Error` is
/// nobody having pressed anything by the time it wanted drawing again.
fn press_within(frame: String, milliseconds: Int) -> Result(key.Key, Nil) {
  case key.read_within(milliseconds) {
    Ok(key.Redraw) -> {
      term.write(term.blank <> frame)
      press_within(frame, milliseconds)
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
  follow(raw, choose(raw, store.saved_games()))
}

fn follow(raw: Bool, chosen: Choice) -> Option(game.Game) {
  case chosen {
    Stop -> None
    Resume(current) -> start(raw, current)
    Play(puzzle) -> start(raw, game.new(puzzle))
    Compose -> compose(raw, editor.new())
    Deal(difficulty) -> {
      // Drawn again as each grid is carved, so a deal that takes a few
      // seconds is visibly a deal taking a few seconds.
      let dealt =
        generator.generate_telling(difficulty, fn(carving) {
          term.write(render.generating(difficulty, carving))
        })

      start(raw, game.new(dealt))
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
  let #(step, ended) = play(raw, store.Unwritten, current)

  case step {
    // Asking for another puzzle abandons this one rather than putting it
    // down, so there is nothing to come back to.
    game.Restart -> {
      store.forget(ended.id)
      run(raw)
    }
    // Not kept here: the parting message does that, so that the saving and
    // the sentence about it are one thing.
    _ -> Some(ended)
  }
}

fn play(
  raw: Bool,
  written: store.Written,
  current: game.Game,
) -> #(game.Step, game.Game) {
  let frame = render.frame(current)
  term.write(frame)

  case waited(raw, current, frame) {
    // Nothing pressed, and the clock has moved: the same game again, with
    // the time it now says. Nothing reaches the rules, which is the point
    // of answering the wait rather than inventing a keystroke for it — a
    // key nobody pressed would put away every offer standing at the time.
    Error(Nil) -> play(raw, kept(current, written), current)

    Ok(pressed) ->
      case rules.update(current, pressed) {
        game.Continue(next) -> {
          let next = judged(current, next)
          play(raw, kept(next, written), next)
        }
        step -> #(step, current)
      }
  }
}

/// Write the game down as it is played, so that a terminal closed, a laptop
/// shut or a fault in here costs half a minute of somebody's puzzle rather
/// than all of it.
///
/// Quietly. A game put down on purpose is worth a sentence about where it
/// went, and there is one on the way out; a game written down every time it
/// changes is worth nothing being said at all. A write that fails is not
/// marked as written, so the next change tries again — and the sentence on
/// the way out still tells the truth about the last of them.
fn kept(current: game.Game, written: store.Written) -> store.Written {
  case store.moved_on(current, written) {
    False -> written
    True -> {
      // The first time this game is written down is the moment to see
      // whether there is room for it, since a game left behind is never
      // going to end and tidy up after itself.
      case written {
        store.Unwritten -> store.make_room()
        _ -> Nil
      }

      case store.keep(current) {
        store.Lost(_) -> written
        _ -> store.written(current)
      }
    }
  }
}

/// Wait for a key, and only for as long as the screen in front of the player
/// goes on being true.
fn waited(
  raw: Bool,
  current: game.Game,
  frame: String,
) -> Result(key.Key, Nil) {
  case counting(raw, current) {
    False -> Ok(press(frame))
    True ->
      press_within(frame, render.until_clock_moves(game.elapsed_ms(current)))
  }
}

/// Whether there is a clock running on the screen to be kept up with.
///
/// A pause and the help have stopped theirs and put the board away besides,
/// and a game that is over has a time rather than a clock. Nor in a terminal
/// that is still in line mode: what is typed there is echoed where it is
/// typed and not handed over until Enter, and a frame landing on top of it
/// would rub out a keystroke halfway through being made.
fn counting(raw: Bool, current: game.Game) -> Bool {
  raw && !current.paused && current.help == None && !game.is_finished(current)
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

/// Show what is on offer and take the answer. The drawing is next door in
/// `render`, so what is on the screen and what a keystroke means are the same
/// list read twice rather than two lists that have to agree.
fn choose(raw: Bool, saved: List(game.Game)) -> Choice {
  let frame = render.menu_frame(raw, saved, store.bests())
  term.write(frame)

  // Worked out rather than written down, so that adding a puzzle to the
  // menu moves this along with it. A guard cannot call for it itself.
  let practice_at = practice.choice()

  case press(frame), saved {
    key.Quit, _ | key.Char("q"), _ | key.Char("Q"), _ -> Stop

    // One game waiting is no question: r has it back. Several is a question,
    // and it is asked on a screen of its own rather than by making the menu
    // guess which of them was meant.
    key.Char("r"), [only] | key.Char("R"), [only] -> Resume(only)
    key.Char("r"), [_, _, ..] | key.Char("R"), [_, _, ..] ->
      picking_up(raw, saved)

    key.Digit(picked), _ if picked == practice_at -> practising(raw, saved)

    key.Digit(picked), _ ->
      case list.drop(generator.origins(), picked - 1) {
        [generator.Dealt(difficulty), ..] -> Deal(difficulty)
        [generator.Handwritten, ..] -> Compose
        _ -> choose(raw, saved)
      }
    _, _ -> choose(raw, saved)
  }
}

/// Pick which game left behind to have back.
///
/// Only ever reached with more than one waiting. Two terminals with a puzzle
/// each is the way that happens, and each keeps its own file so that neither
/// writes over the other; this is where they are told apart again, by what
/// they are rather than by which file they landed in.
fn picking_up(raw: Bool, saved: List(game.Game)) -> Choice {
  let frame = render.saved_frame(saved)
  term.write(frame)

  case press(frame) {
    key.Quit | key.Char("q") | key.Char("Q") -> Stop
    key.Digit(picked) ->
      case list.drop(saved, picked - 1) {
        [current, ..] -> Resume(current)
        [] -> picking_up(raw, saved)
      }
    // Anything else is somebody who has thought better of it, the same as on
    // the screen offering techniques to practise.
    _ -> choose(raw, saved)
  }
}

/// Pick a technique to practise, on the one grid kept for it.
///
/// A screen of its own rather than seven more lines on the menu: the menu is
/// a choice of how hard a puzzle should be, and this is a choice of what to
/// work on, which is a different question asked less often.
fn practising(raw: Bool, saved: List(game.Game)) -> Choice {
  let frame = render.practice_frame()
  term.write(frame)

  case press(frame) {
    key.Quit | key.Char("q") | key.Char("Q") -> Stop
    key.Digit(picked) ->
      case list.drop(practice.techniques(), picked - 1) {
        [technique, ..] ->
          case practice.puzzle(technique) {
            Ok(puzzle) -> Play(puzzle)
            // Only reachable with a grid here that is not a puzzle, which
            // is what the tests are for. Nothing to say about it that the
            // player could act on, so the screen simply stands.
            Error(_) -> practising(raw, saved)
          }
        [] -> practising(raw, saved)
      }
    // Anything else is somebody who opened this by accident, or has thought
    // better of it: back to the menu, the way the help goes back to the board.
    _ -> choose(raw, saved)
  }
}
