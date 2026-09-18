//// What the keyboard means on the screens that choose a puzzle.
////
//// Kept apart from putting them on the screen, the same way `invocation` is
//// kept apart from acting on a command line and `logic` from the board it
//// reasons about. Deciding what a keystroke settles needs no terminal, no
//// files and no puzzle dealt; doing something about it needs all three, and
//// is in the main module.
////
//// Which is also the only way any of it gets tested. The loop next door
//// reads a key and writes a frame, and a test can do neither — so the part
//// that decides anything lives here, where it can be asked a question and
//// answer one. It was the want of that which let a newline pass for a
//// keystroke on two of these screens for as long as it did.

import gleam/list
import gleam/option.{type Option, None}
import sudoku/date.{type Date}
import sudoku/game.{type Game}
import sudoku/generator.{type Difficulty, type Puzzle}
import sudoku/key.{type Key}
import sudoku/logic
import sudoku/practice

/// What the opening screens can settle on, and what the command line can ask
/// for instead. Only the command line asks to play a particular puzzle, or
/// names the seed a deal should come from.
pub type Choice {
  Deal(Difficulty, Option(Int))
  /// The puzzle belonging to a day, which everybody asking for that day gets.
  Day(Date)
  Compose
  Resume(Game)
  Play(Puzzle)
  /// A position where this technique is the step that comes next. Which of
  /// the ones kept for it is not settled here: picking one needs chance, and
  /// building it needs a deal.
  Drill(technique: logic.Technique)
  Stop
}

/// The screens a puzzle can be chosen from.
pub type Screen {
  /// The opening menu.
  Choosing
  /// Which of several games put down to have back. Only ever reached with
  /// more than one waiting: one is no question.
  PickingUp
  /// Which technique to practise, on the one grid kept for it.
  Practising
  /// Which technique to drill, on a fresh position every time.
  Drilling
}

/// What a keystroke settles, on whichever screen it was pressed.
pub type Answer {
  /// Start this.
  Picked(Choice)
  /// Put this screen up instead.
  Opens(Screen)
  /// Nothing was settled. The screen stands as it is, which is the answer to
  /// a key that means nothing here — and to one nobody pressed.
  Stands
}

/// Which number on the menu reaches the daily puzzle.
///
/// After the techniques, which are after the puzzles there are to deal.
/// Worked out rather than written down, so that a puzzle added to the menu
/// moves this along with it instead of quietly landing on top of it — and
/// read by the screen as well as by this, so the two cannot come to
/// disagree about which digit means what.
pub fn daily_choice() -> Int {
  practice.choice() + 1
}

pub fn answered(
  screen: Screen,
  pressed: Key,
  saved: List(Game),
  today: Date,
) -> Answer {
  case screen {
    Choosing -> choosing(pressed, saved, today)
    PickingUp -> picking_up(pressed, saved)
    Practising -> practising(pressed)
    Drilling -> drilling(pressed)
  }
}

/// The opening menu: a level to deal at, a grid to type into, a technique to
/// practise, the day's puzzle, or a game to have back.
fn choosing(pressed: Key, saved: List(Game), today: Date) -> Answer {
  // Worked out rather than written down, so that adding a puzzle to the menu
  // moves these along with it. A guard cannot call for them itself.
  let practice_at = practice.choice()
  let daily_at = daily_choice()

  case pressed, saved {
    key.Quit, _ | key.Char("q"), _ | key.Char("Q"), _ -> Picked(Stop)

    // One game waiting is no question: r has it back. Several is a question,
    // and it is asked on a screen of its own rather than by making the menu
    // guess which of them was meant. None waiting is not an offer at all,
    // and r falls through to meaning nothing.
    key.Char("r"), [only] | key.Char("R"), [only] -> Picked(Resume(only))
    key.Char("r"), [_, _, ..] | key.Char("R"), [_, _, ..] -> Opens(PickingUp)

    key.Digit(picked), _ if picked == practice_at -> Opens(Practising)
    key.Digit(picked), _ if picked == daily_at -> Picked(Day(today))

    key.Digit(picked), _ ->
      case nth(generator.origins(), picked) {
        // Nothing chosen from the menu names a seed: the command line is
        // where a deal is asked for by name, and the menu is where one is
        // asked for by difficulty and left to chance.
        Ok(generator.Dealt(difficulty)) -> Picked(Deal(difficulty, None))
        Ok(generator.Handwritten) -> Picked(Compose)
        _ -> Stands
      }

    _, _ -> Stands
  }
}

/// Pick which game left behind to have back.
///
/// They are told apart by what they are rather than by which file they
/// landed in, a file being the game's business and not the player's.
fn picking_up(pressed: Key, saved: List(Game)) -> Answer {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Picked(Stop)
    key.Digit(picked) ->
      case nth(saved, picked) {
        Ok(current) -> Picked(Resume(current))
        // A digit with no game behind it is a slip, not a change of mind.
        Error(_) -> Stands
      }
    _ -> thought_better(pressed)
  }
}

/// Pick a technique to practise, on the one grid kept for it.
fn practising(pressed: Key) -> Answer {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Picked(Stop)
    // The grid kept for a technique teaches it once. A drill is where to go
    // after that, and it is on a screen of its own because it is a different
    // question: not which technique, but which technique again.
    key.Char("d") | key.Char("D") -> Opens(Drilling)

    key.Digit(picked) ->
      case nth(practice.techniques(), picked) {
        Ok(technique) ->
          case practice.puzzle(technique) {
            Ok(puzzle) -> Picked(Play(puzzle))
            // Only reachable with a grid kept here that is not a puzzle,
            // which is what the tests are for. Nothing to say about it that
            // the player could act on, so the screen simply stands.
            Error(_) -> Stands
          }
        Error(_) -> Stands
      }
    _ -> thought_better(pressed)
  }
}

/// Pick a technique to drill, on a position taken out of a real deal.
fn drilling(pressed: Key) -> Answer {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Picked(Stop)
    key.Digit(picked) ->
      case nth(practice.techniques(), picked) {
        // Only a technique nothing is kept for, which is none of them and
        // is what the tests are for.
        Ok(technique) ->
          case practice.drills_for(technique) {
            [] -> Stands
            [_, ..] -> Picked(Drill(technique))
          }
        Error(_) -> Stands
      }
    _ -> thought_better(pressed)
  }
}

/// The one a digit points at, counting from one the way the screens number
/// them.
///
/// Counting from one is the whole of why this is worth a name. `list.drop`
/// takes a negative count for no count at all and hands back the list
/// entire, so a digit below the first would quietly pick the first — which
/// nothing can press today, `key` making digits only from 1 to 9, and which
/// nothing should be left resting on.
fn nth(values: List(a), picked: Int) -> Result(a, Nil) {
  case picked >= 1, list.drop(values, picked - 1) {
    True, [value, ..] -> Ok(value)
    _, _ -> Error(Nil)
  }
}

/// What a key means on the two screens where anything unrecognised is
/// somebody who opened it by accident: back to the menu.
///
/// Anything unrecognised that the player actually pressed, that is. A
/// terminal in line mode echoes a newline after every key and Enter in raw
/// mode arrives as one, and neither is a keystroke anybody made. Taken for
/// "anything else" they undid the key before them — the digit that chose a
/// technique was answered, and then the Enter that entered it sent the
/// screen back to the menu, where the same digit went on to pick something
/// else entirely without a word said about it.
fn thought_better(pressed: Key) -> Answer {
  case pressed {
    key.Unknown -> Stands
    _ -> Opens(Choosing)
  }
}
