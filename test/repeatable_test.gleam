//// The same puzzle everywhere, not only the same puzzle twice.
////
//// `generator_test` asks whether a seed deals the same grid as itself, which
//// it can answer on the machine it is running on. This asks the other half:
//// whether that grid is the grid everybody else gets. Two people comparing
//// times on the day's puzzle are trusting it, and neither of them can see
//// the other's screen.
////
//// So the numbers below are written down rather than worked out. Nothing in
//// here computes what it expects — that is the point, and it is why these
//// are the only tests in the suite that are meant to be read as a promise
//// rather than as a check.
////
//// What breaks them is a change to how a puzzle is carved, which is fair
//// and wants the new numbers written in — but also a change underneath the
//// game, in the Erlang that shuffles, where nobody would have thought to
//// look. That is the whole of what they are for, and why the workflow runs
//// them on more than the one runtime this was written on.

import sudoku/board
import sudoku/date
import sudoku/generator
import sudoku/random

/// The floor everything else here stands on.
///
/// Every choice chance makes in carving a grid comes through this: the order
/// the digits are tried in filling it, and the order the cells come back out
/// of it. A runtime whose `rand` draws a different stream from the same seed
/// would deal different puzzles from the same seed, and nothing further up
/// would say so — the grids would be perfectly good puzzles, just not the
/// ones anybody else was playing.
pub fn a_seeded_shuffle_is_the_same_shuffle_everywhere_test() {
  random.seed(42)
  assert random.shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9])
    == [3, 9, 1, 6, 8, 7, 5, 4, 2]

  // And seeding again goes back to the same place rather than carrying on.
  random.seed(42)
  assert random.shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9])
    == [3, 9, 1, 6, 8, 7, 5, 4, 2]
}

/// A seed names a deal, and the name has to mean the same thing to whoever
/// is handed it. This is the shortest way that promise can be broken.
pub fn a_named_seed_deals_one_known_puzzle_test() {
  let dealt = generator.generate_from(42, generator.Easy)

  assert board.to_string(dealt.board.values)
    == "3.5.89.7.47..5.2.89.264...112.....46...5.6...56.....392...354.76.1.2..83.4.96.1.5"
}

/// The day's puzzle, which is the promise with the most riding on it: one
/// grid a day and everybody gets the same one, or it is not a daily at all.
///
/// A Thursday, so a Medium, so a quick one to deal. Which day it is does not
/// matter to what is being asked — only that it is a day somebody else could
/// ask for too.
pub fn a_day_deals_one_known_puzzle_test() {
  let on = date.Date(year: 2026, month: 9, day: 17)
  let dealt = generator.deal_daily(on, fn(_) { Nil })

  assert board.to_string(dealt.board.values)
    == "..2...463734..2..1..5.4..2.9..1.8...4.......9...2.4..8.8..5.6..2..8..395579...8.."
}
