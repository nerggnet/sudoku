//// What checking costs, and what it forfeits.

import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key

pub fn the_first_c_only_says_what_the_second_would_do_test() {
  let asked = helper.step(helper.fixture(), key.Char("c"))

  assert !asked.checking
  assert game.unaided(asked)
  assert string.contains(asked.message, "for good")
  assert string.contains(asked.message, "not timed")
  assert string.contains(asked.message, "Press c again")
}

pub fn a_warning_not_taken_up_does_not_keep_test() {
  let wandered =
    helper.fixture() |> helper.step(key.Char("c")) |> helper.step(key.Right)

  // Moving off drops the offer, so c starts over rather than switching on.
  let asked = helper.step(wandered, key.Char("c"))
  assert !asked.checking
  assert string.contains(asked.message, "Press c again")
}

pub fn the_warning_names_a_forfeit_where_one_is_waiting_test() {
  let assert [a, b, c, d, e, ..] = helper.blanks()
  let asked =
    helper.blunder(helper.fixture(), [a, b, c, d, e])
    |> helper.step(key.Char("c"))

  assert !asked.checking
  assert !game.is_finished(asked)
  assert string.contains(asked.message, "5 wrong")
  assert string.contains(asked.message, "forfeits")
}

pub fn a_puzzle_typed_in_is_warned_about_checking_too_test() {
  // No time to lose, but checking still cannot be undone and can still end
  // the puzzle, so it is worth hearing about first.
  let asked = helper.step(helper.handwritten(), key.Char("c"))

  assert !asked.checking
  assert string.contains(asked.message, "for good")
  assert !string.contains(asked.message, "not timed")
  assert helper.checked(helper.handwritten()).checking
}

pub fn checking_allows_three_wrong_digits_test() {
  let assert [a, b, c, ..] = helper.blanks()
  let checked = helper.checked(helper.fixture())

  let once = helper.blunder(checked, [a])
  assert once.mistakes == 1
  assert !game.is_finished(once)
  assert string.contains(once.message, "2 more")

  let twice = helper.blunder(once, [b])
  assert twice.mistakes == 2
  assert string.contains(twice.message, "One more")

  let thrice = helper.blunder(twice, [c])
  assert thrice.mistakes == game.mistake_limit
  assert !game.is_finished(thrice)
  assert string.contains(thrice.message, "next one forfeits")
}

pub fn a_fourth_wrong_digit_forfeits_the_puzzle_test() {
  let assert [a, b, c, d, ..] = helper.blanks()

  let lost = helper.blunder(helper.checked(helper.fixture()), [a, b, c, d])

  assert lost.mistakes == game.mistake_limit + 1
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)

  // A forfeited puzzle takes no more digits, and says how to start again.
  let poked = game.Game(..lost, cursor: a) |> helper.step(key.Erase)
  assert board.value(poked.board, a) == board.value(lost.board, a)
  assert string.contains(poked.message, "new puzzle")
}

pub fn wrong_digits_are_free_until_checking_is_asked_for_test() {
  let assert [a, b, c, d, ..] = helper.blanks()

  let unchecked = helper.blunder(helper.fixture(), [a, b, c, d])
  assert unchecked.mistakes == 0
  assert !game.is_finished(unchecked)
  assert !string.contains(unchecked.message, "forfeit")
}

pub fn switching_checking_on_charges_for_what_it_finds_test() {
  let assert [a, b, c, ..] = helper.blanks()

  // Free while the game was saying nothing about them; asking puts all three
  // on the tally at once, or they could be banked up and cashed in for one
  // keystroke's worth of answers.
  let checked = helper.checked(helper.blunder(helper.fixture(), [a, b, c]))

  assert checked.mistakes == 3
  assert string.contains(checked.message, "3 digits are wrong")
  assert string.contains(checked.message, "next one forfeits")

  // Spent to the last of it, but still playing.
  assert !game.is_finished(checked)
}

pub fn switching_checking_on_to_too_many_forfeits_test() {
  let assert [a, b, c, d, e, ..] = helper.blanks()
  let lost = helper.checked(helper.blunder(helper.fixture(), [a, b, c, d, e]))

  // Five wrong digits is past the allowance, so asking ends it there.
  assert lost.mistakes == 5
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)
  assert list.any(helper.visible_lines(lost), string.contains(
    _,
    "5 wrong digits",
  ))
}

pub fn spent_to_the_last_the_next_wrong_digit_ends_it_test() {
  let assert [a, b, c, d, ..] = helper.blanks()
  let spent = helper.checked(helper.blunder(helper.fixture(), [a, b, c]))

  // Putting the three right again costs nothing, though the tally stands.
  let mended = {
    use current, index <- list.fold([a, b, c], spent)
    game.Game(..current, cursor: index)
    |> helper.step(key.Digit(game.answer(current, index)))
  }
  assert !game.is_finished(mended)
  assert mended.mistakes == 3

  // One more wrong digit written, and it is over.
  let lost = helper.blunder(mended, [d])
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)
}

pub fn right_digits_cost_nothing_test() {
  let checked = helper.checked(helper.fixture())

  let played = {
    use current, index <- list.fold(list.take(helper.blanks(), 5), checked)
    game.Game(..current, cursor: index)
    |> helper.step(key.Digit(game.answer(current, index)))
  }

  assert played.mistakes == 0
  assert !game.is_finished(played)
}

pub fn writing_the_same_wrong_digit_again_costs_nothing_test() {
  let assert [a, ..] = helper.blanks()
  let once = helper.blunder(helper.checked(helper.fixture()), [a])

  // The cell already holds it, so nothing has changed and nothing is owed.
  let again =
    game.Game(..once, cursor: a)
    |> helper.step(key.Digit(board.value(once.board, a)))
  assert again.mistakes == 1
}

pub fn undo_takes_back_the_digit_but_not_the_mistake_test() {
  let assert [a, ..] = helper.blanks()
  let once = helper.blunder(helper.checked(helper.fixture()), [a])
  let undone = helper.step(once, key.Char("u"))

  assert board.value(undone.board, a) == 0
  assert undone.mistakes == 1
}

pub fn the_tally_shows_on_the_title_line_test() {
  let assert [a, ..] = helper.blanks()
  let checked = helper.checked(helper.fixture())

  // It appears as soon as checking is on, before anything is spent.
  assert list.any(helper.visible_lines(checked), string.contains(
    _,
    "checking 0/3",
  ))

  let once = helper.blunder(checked, [a])
  assert list.any(helper.visible_lines(once), string.contains(_, "checking 1/3"))

  // Checking cannot be switched off, so it and the tally stay up.
  let again = helper.step(once, key.Char("c"))
  assert again.checking
  assert list.any(helper.visible_lines(again), string.contains(
    _,
    "checking 1/3",
  ))

  // A game that has never checked says nothing about it.
  assert !list.any(helper.visible_lines(helper.fixture()), string.contains(
    _,
    "checking",
  ))
}

pub fn forfeiting_says_so_test() {
  let assert [a, b, c, d, ..] = helper.blanks()
  let lost = helper.blunder(helper.checked(helper.fixture()), [a, b, c, d])
  let lines = helper.visible_lines(lost)

  assert list.any(lines, string.contains(_, "forfeited"))
  assert list.any(lines, string.contains(_, "n new puzzle"))
  // The panel has the last word; no tally reading four out of three.
  assert !list.any(lines, string.contains(_, "checking"))
  // The board is left standing, so the mistakes can be seen.
  assert list.any(lines, helper.is_grid_row)
}

pub fn checking_counts_wrong_digits_test() {
  // A3 is a 4 in the solution, so a 1 there is wrong.
  let played = helper.step(helper.fixture(), key.Digit(1))
  assert game.is_wrong(played, 2)

  let checked = helper.checked(played)
  assert checked.checking
  assert string.contains(checked.message, "1 digit is wrong")

  // Pressing it again does not turn checking back off. It cannot be.
  let again = helper.step(checked, key.Char("c"))
  assert again.checking
  assert string.contains(again.message, "stays on")
}
