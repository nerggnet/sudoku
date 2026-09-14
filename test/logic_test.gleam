//// Reasoning an answer out the way a person does.

import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/generator
import sudoku/logic
import sudoku/solver

pub fn reasoning_solves_an_ordinary_puzzle_test() {
  let #(steps, reasoned) = logic.unfold(helper.grid(helper.puzzle_text))

  assert board.to_string(reasoned)
    == board.to_string(helper.grid(helper.solution_text))
  assert steps != []
}

/// The test that carries the others: whatever a technique claims, it has to
/// agree with the answer the puzzle was carved from. A digit settled is the
/// digit that belongs there, and a digit ruled out is never the one that did.
pub fn every_step_agrees_with_the_answer_test() {
  use difficulty <- list.each(generator.difficulties)
  let puzzle = generator.generate(difficulty)
  let #(steps, _) = logic.unfold(puzzle.board.values)

  use step <- list.each(steps)
  case step.move {
    logic.Settle(index, digit) -> {
      assert dict.get(puzzle.solution, index) == Ok(digit)
    }
    logic.RuleOut(cells, digits) -> {
      use index <- list.each(cells)
      let assert Ok(answer) = dict.get(puzzle.solution, index)
      assert !list.contains(digits, answer)
    }
  }
}

pub fn a_step_always_changes_something_test() {
  // A technique that ruled nothing out would be reported for ever.
  let puzzle = generator.generate(generator.Hard)
  let #(steps, _) = logic.unfold(puzzle.board.values)

  use step <- list.each(steps)
  case step.move {
    logic.Settle(_, _) -> Nil
    logic.RuleOut(cells, digits) -> {
      assert cells != []
      assert digits != []
    }
  }
}

pub fn the_simplest_step_comes_first_test() {
  // One cell left blank can only be a naked single.
  let one_short = dict.insert(helper.grid(helper.solution_text), 40, 0)
  let assert Ok(step) = logic.next(one_short)

  assert step.technique == logic.NakedSingle
  assert step.move == logic.Settle(40, 5)
  assert step.evidence == [40]
}

pub fn a_hint_names_a_digit_that_belongs_test() {
  let assert Ok(step) = logic.next(helper.grid(helper.puzzle_text))
  let assert logic.Settle(index, digit) = step.move

  assert dict.get(helper.grid(helper.solution_text), index) == Ok(digit)
  // Nothing harder than a single is needed to get started here.
  assert logic.rank(step.technique) <= logic.rank(logic.HiddenSingle)
}

pub fn reasoning_runs_out_on_an_empty_grid_test() {
  // Every cell can take anything, so no technique has anything to say.
  let #(steps, reasoned) = logic.unfold(board.empty_grid())

  assert steps == []
  assert reasoned == board.empty_grid()
  assert logic.rate(board.empty_grid()) == Error(Nil)
}

pub fn a_finished_grid_asks_nothing_test() {
  assert logic.rate(helper.grid(helper.solution_text)) == Ok(logic.NakedSingle)
}

pub fn a_puzzle_is_rated_by_its_hardest_step_test() {
  let assert Ok(rating) = logic.rate(helper.grid(helper.puzzle_text))
  let #(steps, _) = logic.unfold(helper.grid(helper.puzzle_text))

  // Nothing harder was used, and the rating was really used.
  use step <- list.each(steps)
  assert logic.rank(step.technique) <= logic.rank(rating)
}

pub fn an_explanation_names_what_it_is_about_test() {
  let hard_cases = [
    #(helper.needs_naked_pair, logic.NakedPair),
    #(helper.needs_hidden_pair, logic.HiddenPair),
    #(helper.needs_naked_triple, logic.NakedTriple),
    #(helper.needs_x_wing, logic.XWing),
    #(helper.puzzle_text, logic.NakedSingle),
  ]

  use #(text, technique) <- list.each(hard_cases)
  let #(steps, _) = logic.unfold(helper.grid(text))
  let assert Ok(step) =
    list.find(steps, fn(step) { step.technique == technique })
  let #(what, why) = logic.explain(step)

  // It names the technique, so the player has something to look up and to
  // recognise the next time it comes round.
  assert string.starts_with(
    string.lowercase(what),
    string.lowercase(logic.label(technique)),
  )

  // Both rows read as sentences rather than a dump of the working, and both
  // fit the status line.
  assert string.ends_with(what, ".")
  assert string.ends_with(why, ".")
  assert string.length(what) < 78
  assert string.length(why) < 78

  // The second row says why, so it is never the first one over again.
  assert why != what

  use digit <- list.each(step.about)
  assert string.contains(what, int.to_string(digit))
}

pub fn techniques_are_listed_easiest_first_test() {
  let ranks = list.map(logic.techniques, logic.rank)

  assert ranks == list.sort(ranks, by: int.compare)
  assert list.unique(ranks) == ranks
  // Every technique is listed, and every one has a name.
  assert list.length(logic.techniques) == 7
  assert list.all(logic.techniques, fn(t) { logic.label(t) != "" })
}

pub fn the_rarer_techniques_are_used_where_they_are_needed_test() {
  let hard_cases = [
    #(helper.needs_naked_pair, logic.NakedPair),
    #(helper.needs_hidden_pair, logic.HiddenPair),
    #(helper.needs_naked_triple, logic.NakedTriple),
    #(helper.needs_x_wing, logic.XWing),
  ]

  use #(text, technique) <- list.each(hard_cases)
  let start = helper.grid(text)
  let #(steps, _) = logic.unfold(start)
  let assert Ok(answer) = solver.solve(start) as "the fixtures are solvable"

  // The technique really is called for here...
  assert list.any(steps, fn(step) { step.technique == technique })

  // ...and every step of the way agrees with the answer the search finds,
  // which is the two solvers checking each other.
  use step <- list.each(steps)
  case step.move {
    logic.Settle(index, digit) -> {
      assert dict.get(answer, index) == Ok(digit)
    }
    logic.RuleOut(cells, digits) -> {
      use index <- list.each(cells)
      let assert Ok(right) = dict.get(answer, index)
      assert !list.contains(digits, right)
    }
  }
}
