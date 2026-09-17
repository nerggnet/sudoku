//// Dealing, and dealing the same puzzle twice.
////
//// Everything here deals at Easy or Medium. A deal is the slowest thing the
//// game does and an Expert one is the slowest of those; what is being
//// tested is that chance is led by the seed, and chance is led the same way
//// at every difficulty.

import gleam/list
import gleam/option.{None, Some}
import sudoku/board
import sudoku/generator
import sudoku/logic
import sudoku/practice

pub fn the_same_seed_deals_the_same_puzzle_test() {
  let once = generator.generate_from(4711, generator.Easy)
  let again = generator.generate_from(4711, generator.Easy)

  assert once.board.values == again.board.values
  assert once.solution == again.solution
  assert once.origin == again.origin
}

/// Not a law of the world — two seeds could in principle carve the same grid
/// — but a grid has some 6 x 10^21 fillings and a carving takes a few dozen
/// coin flips on top of that, so two of these landing together would mean
/// the seed was not reaching the chance at all.
pub fn different_seeds_deal_different_puzzles_test() {
  let one = generator.generate_from(1, generator.Easy)
  let other = generator.generate_from(2, generator.Easy)

  assert one.board.values != other.board.values
}

/// The seed is worth nothing if the deal only follows it the first time. A
/// second deal in between is what a session looks like — somebody presses n
/// — and it must not carry over into the third.
pub fn a_seed_is_followed_however_much_came_before_it_test() {
  let first = generator.generate_from(99, generator.Medium)
  let _ = generator.generate_from(12_345, generator.Easy)
  let _ = generator.generate(generator.Easy)
  let again = generator.generate_from(99, generator.Medium)

  assert first.board.values == again.board.values
}

pub fn a_dealt_puzzle_says_which_seed_dealt_it_test() {
  assert generator.generate_from(2024, generator.Easy).seed == Some(2024)

  // Including one dealt from a seed nobody chose, which is still a seed and
  // still deals it again.
  let dealt = generator.generate(generator.Easy)
  let assert Some(seed) = dealt.seed
  assert generator.generate_from(seed, generator.Easy).board.values
    == dealt.board.values
}

/// A seed nobody chose is chosen afresh each time. Drawn from `rand` it
/// would not be: the deal seeds `rand` on its way past, so the second call
/// would hand back whatever the first deal's own seeding made of it.
pub fn a_fresh_seed_is_fresh_each_time_test() {
  let one = generator.generate(generator.Easy)
  let other = generator.generate(generator.Easy)

  assert one.seed != other.seed
}

/// Nothing else has a seed, because nothing else was dealt. A grid typed in
/// came from a newspaper and a practice grid is the same one every time.
pub fn a_puzzle_nobody_dealt_has_no_seed_test() {
  let assert Ok(typed) =
    generator.from_clues(
      generator.generate_from(7, generator.Easy).board.values,
    )
  assert typed.seed == None

  use technique <- list.each(logic.techniques)
  let assert Ok(kept) = practice.puzzle(technique)
  assert kept.seed == None
}

/// A seeded deal is still a deal: the same promises hold about what comes
/// out of it, whoever named the seed.
pub fn a_seeded_deal_is_still_a_proper_puzzle_test() {
  use difficulty <- list.each([generator.Easy, generator.Medium])
  let puzzle = generator.generate_from(31_337, difficulty)

  assert puzzle.origin == generator.Dealt(difficulty)
  assert board.is_consistent(puzzle.board.values)
  assert board.is_solved(board.from_grid(puzzle.solution))

  // Exactly one answer, and reachable without a guess.
  assert board.grid_conflicts(puzzle.solution) == board.conflicts(puzzle.board)
  assert logic.rate(puzzle.board.values) != Error(Nil)
}
