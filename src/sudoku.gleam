//// A Sudoku game for the terminal.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import sudoku/board
import sudoku/date
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/help
import sudoku/invocation
import sudoku/key
import sudoku/menu
import sudoku/practice
import sudoku/random
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
        True -> term.colouring(term.Plain)
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

      term.tell("Thanks for playing.")
      parting(played)
    }
  }
}

/// What the words the game was started with leave it to do.
type Opening {
  /// Play: this, or the menu where nothing was named.
  Start(chosen: Option(menu.Choice), plain: Bool)
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
        // The one answer here that cannot be worked out from the words
        // alone, the version being a fact about the build rather than about
        // the line. Which is why it is settled here rather than in
        // `invocation`, where nothing is allowed to ask the world anything.
        invocation.Name -> Say("sudoku " <> term.version(), True)
        invocation.Menu -> Start(None, asked.plain)
        invocation.Compose -> Start(Some(menu.Compose), asked.plain)
        invocation.Deal(difficulty) ->
          Start(Some(menu.Deal(difficulty, asked.seed)), asked.plain)
        invocation.Today -> Start(Some(menu.Day(date.today())), asked.plain)
        invocation.Day(on) -> Start(Some(menu.Day(on)), asked.plain)
        invocation.Play(puzzle) -> Start(Some(menu.Play(puzzle)), asked.plain)
        invocation.Resume ->
          case store.saved() {
            Ok(current) -> Start(Some(menu.Resume(current)), asked.plain)
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
    store.PutDown(where) -> term.tell("\nSaved in " <> where)
    store.Lost(where) -> term.tell("\nCould not save in " <> where <> ".")
  }

  term.tell("\nThis puzzle:")
  term.tell(board.to_string(current.puzzle.board.values))

  // And the shorter way to say the same thing, where there is one. Eighty-one
  // characters are for handing a puzzle to somebody who has never run this;
  // a seed is for handing this one back to the game that dealt it, which is
  // what somebody wants who liked the puzzle, or who did not and would like
  // to say why.
  case current.puzzle.seed, current.puzzle.origin {
    Some(seed), generator.Dealt(difficulty) ->
      term.tell(
        "\nDealt at "
        <> generator.label(difficulty)
        <> " from seed "
        <> int.to_string(seed)
        <> ", which deals it again.",
      )
    // A daily says its day instead. The day is its seed and its name at
    // once: it is what somebody else types to be handed the same grid, and
    // the only part of it worth passing on.
    _, generator.Daily(on) ->
      term.tell(
        "\nThe daily puzzle for "
        <> date.to_string(on)
        <> ", which deals it again.",
      )
    _, _ -> Nil
  }
}

fn option_each(value: Option(a), run: fn(a) -> Nil) -> Nil {
  case value {
    Some(value) -> run(value)
    None -> Nil
  }
}

/// Read a key the player actually pressed, drawing the screen again for as
/// long as that is what is asked for.
///
/// Every screen is drawn the same way, so this can answer Ctrl-L wherever it
/// is pressed without any of them knowing about it. Wiping first is the point
/// of it: an ordinary frame clears each line as it lands, which is no use
/// against a mess made by something other than the game.
///
/// A newline is swallowed here for the same reason and in the same place. A
/// terminal in line mode echoes one after every key, and Enter in raw mode
/// arrives as one too; neither is a keystroke anybody made. The board and
/// the editor each knew that and said so themselves, and the screens that
/// pick a puzzle did not — they read it as "anything else", which on those
/// screens means "go back". So picking a technique to practise, or which
/// game to pick up, was answered and then undone by the Enter that answered
/// it, and in line mode there was no way to reach either screen at all.
fn press(frame: String) -> key.Key {
  case key.read() {
    key.Redraw -> {
      term.write(term.blank <> frame)
      press(frame)
    }
    key.Unknown -> press(frame)
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
    Ok(key.Unknown) -> press_within(frame, milliseconds)
    pressed -> pressed
  }
}

fn run(raw: Bool) -> Option(game.Game) {
  follow(raw, showing(raw, menu.Choosing, store.saved_games()))
}

/// Put a screen up, read a key, and do as it says: open another screen, or
/// hand back the choice it settled.
///
/// One function for the three of them, because the three are one thing done
/// three times: draw, read, decide. What each of them draws is next door in
/// `render` and what each of them decides is next door in `menu`, so the
/// list on the screen and the keystrokes that read it are the same list read
/// twice rather than two lists that have to agree.
fn showing(
  raw: Bool,
  screen: menu.Screen,
  saved: List(game.Game),
) -> menu.Choice {
  // Asked as the screen is drawn rather than as it is read, so that a menu
  // sat in front of since before midnight goes on offering the day it says
  // it is offering.
  let today = date.today()

  let frame = case screen {
    menu.Choosing ->
      render.menu_frame(raw, saved, store.bests(), today, store.dailies())
    menu.PickingUp -> render.saved_frame(saved)
    menu.Forgetting -> render.forgetting_frame(saved)
    menu.Practising -> render.practice_frame()
    menu.Drilling -> render.drill_frame()
  }
  term.write(frame)

  case menu.answered(screen, press(frame), saved, today) {
    menu.Picked(chosen) -> chosen
    menu.Opens(next) -> showing(raw, next, saved)
    menu.Stands -> showing(raw, screen, saved)

    // Thrown away, and then the list again so that more can go the same way
    // — which is the point of the screen, a list that only ever lost its
    // oldest being the thing that made it worth having. The games are read
    // afresh rather than filtered here: what is on the disk is what there is.
    menu.Forgets(gone) -> {
      store.forget(gone.id)

      case store.saved_games() {
        [] -> showing(raw, menu.Choosing, [])
        left -> showing(raw, menu.Forgetting, left)
      }
    }
  }
}

fn follow(raw: Bool, chosen: menu.Choice) -> Option(game.Game) {
  case chosen {
    menu.Stop -> None
    menu.Resume(current) -> start(raw, current)
    menu.Play(puzzle) -> start(raw, game.new(puzzle))
    menu.Compose -> compose(raw, editor.new())
    menu.Deal(difficulty, seed) -> {
      // Settled here rather than left to the generator, so that every deal
      // has a seed worth printing whether or not anybody asked for one.
      let seed = option.lazy_unwrap(seed, random.fresh_seed)

      // Drawn again as each grid is carved, so a deal that takes a few
      // seconds is visibly a deal taking a few seconds.
      let dealt =
        generator.generate_telling(seed, difficulty, fn(carving) {
          term.write(render.generating(difficulty, carving))
        })

      start(raw, game.new(dealt))
    }

    // Which of the positions kept for it is chance's to settle, and getting
    // back to one means dealing the puzzle it came out of — which is why the
    // carving screen goes up for it, the same as for a deal.
    menu.Drill(technique) -> {
      let kept = practice.drills_for(technique)
      let at = random.fresh_seed() % int.max(list.length(kept), 1)

      case list.drop(kept, at) {
        [drill, ..] -> {
          let position =
            practice.drilled(technique, drill, fn(carving) {
              term.write(render.generating(drill.difficulty, carving))
            })
          start(raw, game.new(position))
        }
        // Nothing kept for it, which the menu does not offer.
        [] -> run(raw)
      }
    }

    menu.Day(on) -> {
      let dealt =
        generator.deal_daily(on, fn(carving) {
          term.write(render.generating(generator.daily_difficulty(on), carving))
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
  case render.clock_runs(raw, current) {
    False -> Ok(press(frame))
    True ->
      press_within(frame, render.until_clock_moves(game.elapsed_ms(current)))
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
