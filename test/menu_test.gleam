//// What the keyboard means on the screens that choose a puzzle.
////
//// These screens had no test at all until now, the loop they live in being
//// one a test cannot drive: it reads a key and writes a frame. So the
//// deciding was lifted out of the doing, and this is what that was for.

import gleam/list
import gleam/option.{None}
import helper
import sudoku/date
import sudoku/game
import sudoku/generator
import sudoku/key
import sudoku/menu
import sudoku/practice

fn answered(screen: menu.Screen, pressed: key.Key) -> menu.Answer {
  menu.answered(screen, pressed, [], helper.a_day())
}

fn with_saved(
  screen: menu.Screen,
  pressed: key.Key,
  saved: List(game.Game),
) -> menu.Answer {
  menu.answered(screen, pressed, saved, helper.a_day())
}

// ---------------------------------------------------------------------------
// The newline that undid the key before it
// ---------------------------------------------------------------------------

/// The bug this module was pulled out to make testable.
///
/// A terminal in line mode echoes a newline after every key, and Enter in
/// raw mode arrives as one too. Both decode to `Unknown`, and on the two
/// screens where anything unrecognised means "go back" they used to mean it
/// as well — so the digit that chose a technique was answered and then
/// undone, and the menu behind it read the same digit as something else.
pub fn a_newline_settles_nothing_anywhere_test() {
  use screen <- list.each([menu.Choosing, menu.PickingUp, menu.Practising])
  assert answered(screen, key.Unknown) == menu.Stands
}

/// And the screen it was pressed on is the screen still up, rather than the
/// menu: standing is not the same as going back.
pub fn a_newline_does_not_go_back_test() {
  use screen <- list.each([menu.PickingUp, menu.Practising])

  assert answered(screen, key.Unknown) != menu.Opens(menu.Choosing)
  // Where a key the player really pressed does go back.
  assert answered(screen, key.Char("z")) == menu.Opens(menu.Choosing)
}

// ---------------------------------------------------------------------------
// The opening menu
// ---------------------------------------------------------------------------

/// The digits are the levels in order, then the grid to type into. Worked
/// out from the same list the screen draws, so a level added moves both.
pub fn the_digits_deal_the_levels_in_order_test() {
  use difficulty, at <- list.index_map(generator.difficulties)
  assert answered(menu.Choosing, key.Digit(at + 1))
    == menu.Picked(menu.Deal(difficulty, None))
}

pub fn the_digit_after_the_levels_types_one_in_test() {
  let at = list.length(generator.difficulties) + 1
  assert answered(menu.Choosing, key.Digit(at)) == menu.Picked(menu.Compose)
}

pub fn practice_and_the_daily_follow_the_puzzles_test() {
  assert answered(menu.Choosing, key.Digit(practice.choice()))
    == menu.Opens(menu.Practising)

  assert answered(menu.Choosing, key.Digit(menu.daily_choice()))
    == menu.Picked(menu.Day(helper.a_day()))

  // In that order, and each after the puzzles there are to deal.
  assert practice.choice() == list.length(generator.origins()) + 1
  assert menu.daily_choice() == practice.choice() + 1
}

/// The day offered is the day it was asked about, rather than one this
/// works out for itself. What day it is is a question about the world, and
/// the world is next door.
pub fn the_daily_is_the_day_it_was_handed_test() {
  let midsummer = date.Date(year: 2026, month: 6, day: 21)
  assert menu.answered(
      menu.Choosing,
      key.Digit(menu.daily_choice()),
      [],
      midsummer,
    )
    == menu.Picked(menu.Day(midsummer))
}

pub fn a_digit_past_the_end_settles_nothing_test() {
  assert answered(menu.Choosing, key.Digit(9)) == menu.Stands
}

pub fn q_stops_from_every_screen_test() {
  use screen <- list.each([menu.Choosing, menu.PickingUp, menu.Practising])
  use pressed <- list.each([key.Quit, key.Char("q"), key.Char("Q")])
  assert answered(screen, pressed) == menu.Picked(menu.Stop)
}

// ---------------------------------------------------------------------------
// Picking a game back up
// ---------------------------------------------------------------------------

/// One game waiting is no question and r has it back. Several is a
/// question, and it is asked on a screen of its own rather than by making
/// the menu guess which of them was meant.
pub fn r_has_one_game_back_and_asks_about_several_test() {
  let one = helper.fixture()
  let other = helper.playing(helper.puzzle_text)

  use pressed <- list.each([key.Char("r"), key.Char("R")])

  assert with_saved(menu.Choosing, pressed, [one])
    == menu.Picked(menu.Resume(one))
  assert with_saved(menu.Choosing, pressed, [one, other])
    == menu.Opens(menu.PickingUp)

  // None waiting is not an offer at all, so r means nothing.
  assert with_saved(menu.Choosing, pressed, []) == menu.Stands
}

pub fn the_digits_pick_which_game_to_have_back_test() {
  let one = helper.fixture()
  let other = helper.playing(helper.puzzle_text)
  let saved = [one, other]

  assert with_saved(menu.PickingUp, key.Digit(1), saved)
    == menu.Picked(menu.Resume(one))
  assert with_saved(menu.PickingUp, key.Digit(2), saved)
    == menu.Picked(menu.Resume(other))

  // A digit past the end of the list is a slip rather than a change of mind,
  // so the screen stands instead of dropping the question.
  assert with_saved(menu.PickingUp, key.Digit(3), saved) == menu.Stands
}

// ---------------------------------------------------------------------------
// Practising
// ---------------------------------------------------------------------------

/// Every technique on the screen is reachable by the digit in front of it,
/// and the grid it reaches is the one kept for that technique.
pub fn the_digits_reach_every_technique_test() {
  use technique, at <- list.index_map(practice.techniques())
  let assert menu.Picked(menu.Play(puzzle)) =
    answered(menu.Practising, key.Digit(at + 1))

  assert puzzle.origin == generator.Practising(technique)
}

/// Nine techniques fill the digits exactly, so there is no tenth key to
/// press. The digit with nothing behind it is the one below the first —
/// which `key` will not make, and which must not pick the first anyway:
/// `list.drop` hands back the whole list for a negative count.
pub fn a_digit_below_the_first_settles_nothing_test() {
  use screen <- list.each([menu.Choosing, menu.PickingUp, menu.Practising])
  assert menu.answered(screen, key.Digit(0), [helper.fixture()], helper.a_day())
    == menu.Stands
}
