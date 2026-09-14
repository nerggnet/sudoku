//// Searching for an answer, and carving a puzzle out of one.

import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import helper
import sudoku/board
import sudoku/generator
import sudoku/logic
import sudoku/solver

pub fn solver_finds_the_solution_test() {
  let assert Ok(solved) = solver.solve(helper.grid(helper.puzzle_text))
  assert board.to_string(solved)
    == board.to_string(helper.grid(helper.solution_text))
}

pub fn solver_leaves_a_finished_grid_alone_test() {
  let assert Ok(solved) = solver.solve(helper.grid(helper.solution_text))
  assert board.to_string(solved)
    == board.to_string(helper.grid(helper.solution_text))
}

pub fn solver_rejects_a_contradictory_grid_test() {
  // Two 1s in the top row. Rejected up front rather than searched for.
  let clashing = dict.insert(dict.insert(board.empty_grid(), 0, 1), 1, 1)
  assert solver.solve(clashing) == Error(Nil)
  assert solver.solve_random(clashing) == Error(Nil)
  assert solver.count_solutions(clashing, 5) == 0
}

pub fn solver_rejects_a_dead_end_test() {
  // Consistent so far, but A1 is left with no legal digit: the rest of its
  // row, column and box between them use up all nine.
  let dead_end =
    helper.grid(
      ".23 456 789
       1.. ... ...
       4.. ... ...
       7.. ... ...
       2.. ... ...
       5.. ... ...
       8.. ... ...
       3.. ... ...
       6.. ... ...",
    )
  assert solver.solve(dead_end) == Error(Nil)
}

pub fn solver_fills_the_empty_grid_test() {
  let assert Ok(filled) = solver.solve_random(board.empty_grid())
  assert board.is_solved(board.from_grid(filled))
}

pub fn a_proper_puzzle_has_exactly_one_solution_test() {
  assert solver.count_solutions(helper.grid(helper.puzzle_text), 5) == 1
}

pub fn too_few_clues_allow_many_solutions_test() {
  // Blanking every 1 and every 2 leaves a grid that can be finished two ways,
  // since the two digits can be swapped throughout.
  let loosened =
    helper.grid(helper.solution_text)
    |> dict.map_values(fn(_index, digit) {
      case digit {
        1 | 2 -> 0
        _ -> digit
      }
    })

  assert solver.count_solutions(loosened, 5) == 2
}

pub fn counting_stops_at_the_limit_test() {
  assert solver.count_solutions(board.empty_grid(), 3) == 3
}

pub fn generated_puzzles_are_well_formed_test() {
  use difficulty <- list.each([generator.Easy, generator.Hard])
  let puzzle = generator.generate(difficulty)

  assert puzzle.origin == generator.Dealt(difficulty)
  assert board.is_solved(board.from_grid(puzzle.solution))
  assert set.is_empty(board.conflicts(puzzle.board))

  // Every clue agrees with the solution it was carved from.
  use index <- list.each(board.indices())
  case board.value(puzzle.board, index) {
    0 -> Nil
    digit -> {
      assert Ok(digit) == dict.get(puzzle.solution, index)
    }
  }
}

pub fn generated_puzzles_have_one_answer_test() {
  let puzzle = generator.generate(generator.Medium)
  assert solver.count_solutions(puzzle.board.values, 5) == 1
}

/// The promise a difficulty makes: a dealt puzzle can always be reasoned out,
/// and never asks for more reasoning than the level it came from allows.
pub fn generated_puzzles_can_be_reasoned_out_test() {
  use difficulty <- list.each(generator.difficulties)
  let puzzle = generator.generate(difficulty)

  let assert Ok(needed) = logic.rate(puzzle.board.values)
    as "a dealt puzzle never needs a guess"
  assert logic.rank(needed) <= logic.rank(generator.hardest(difficulty))

  // And it is still a puzzle: carving never goes below the 17-clue floor.
  assert 81 - board.empty_count(puzzle.board) >= 17
}

pub fn a_difficulty_can_be_named_test() {
  // What the command line takes, in any capitalisation.
  use difficulty <- list.each(generator.difficulties)
  let name = generator.label(difficulty)

  assert generator.named(name) == Ok(difficulty)
  assert generator.named(string.lowercase(name)) == Ok(difficulty)
  assert generator.named(string.uppercase(name)) == Ok(difficulty)
}

pub fn nothing_else_is_a_difficulty_test() {
  assert generator.named("custom") == Error(Nil)
  assert generator.named("") == Error(Nil)
  assert generator.named("hardest") == Error(Nil)
}

pub fn difficulty_ceilings_ascend_test() {
  let ceilings = {
    use difficulty <- list.map(generator.difficulties)
    logic.rank(generator.hardest(difficulty))
  }

  assert ceilings == list.sort(ceilings, by: int.compare)
  assert list.unique(ceilings) == ceilings
}
