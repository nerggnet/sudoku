//// Being walked up to a technique.
////
//// Every grid here is one of the nine kept for practising, so the positions
//// are the same every time and the ladder can be asserted word for word.

import gleam/int
import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/logic
import sudoku/practice
import sudoku/rules
import sudoku/tutor

/// A practice game with the candidates pencilled in, which is where an
/// argument about candidates has to start.
fn practising(technique: logic.Technique) -> game.Game {
  let assert Ok(puzzle) = practice.puzzle(technique)
  let assert game.Continue(filled) =
    rules.update(game.new(puzzle), key.Char("f"))

  filled
}

/// Do what a player following the reasoning does — play the settles, rub out
/// the marks that are ruled out — until the technique being practised is the
/// step that comes next.
fn at_the_moment(technique: logic.Technique) -> game.Game {
  advanced(practising(technique), technique, 60)
}

fn advanced(
  current: game.Game,
  technique: logic.Technique,
  left: Int,
) -> game.Game {
  case left, logic.next_from(current.board.values, game.reading(current)) {
    0, _ -> current
    _, Error(_) -> current
    _, Ok(step) ->
      case step.technique == technique {
        True -> current
        False ->
          advanced(
            game.with_board(current, played(current, step)),
            technique,
            left - 1,
          )
      }
  }
}

fn played(current: game.Game, step: logic.Step) -> board.Board {
  case step.move {
    logic.Settle(index, digit) -> board.place(current.board, index, digit)
    logic.RuleOut(cells, digits) -> {
      use board, index <- list.fold(cells, current.board)
      use board, digit <- list.fold(digits, board)
      board.erase_mark(board, index, digit)
    }
  }
}

fn said(current: game.Game, asked: Int) -> String {
  let lesson = tutor.lesson(current, asked)
  lesson.what <> " " <> lesson.why
}

// ---------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------

/// Each rung says a little more than the one before it, and the first says
/// the least that is still worth knowing: that this is the moment.
pub fn the_ladder_says_more_a_rung_at_a_time_test() {
  let at = at_the_moment(logic.XWing)

  let first = tutor.lesson(at, 1)
  assert string.contains(first.what, "X-wing")
  assert string.contains(first.what, "the moment")
  assert string.contains(first.why, "Nothing simpler")
  // The digit the step is about, and nothing about where it is.
  let assert Ok(step) = logic.next_from(at.board.values, game.reading(at))
  use digit <- list.each(step.about)
  assert string.contains(first.why, int.to_string(digit))
  assert first.lit == []

  let second = tutor.lesson(at, 2)
  assert string.contains(second.what, "row")
  assert second.lit == []

  let third = tutor.lesson(at, 3)
  use corner <- list.each(step.evidence)
  assert string.contains(third.what, board.name(corner))
  assert third.lit == step.evidence

  let fourth = tutor.lesson(at, 4)
  assert #(fourth.what, fourth.why) == explained(at)
}

fn explained(current: game.Game) -> #(String, String) {
  let assert Ok(step) =
    logic.next_from(current.board.values, game.reading(current))
  logic.explain(step)
}

/// The cells only light once the tutor has got as far as naming them.
/// Lighting them at the first nudge would be the answer rather than a nudge.
pub fn the_cells_light_only_once_they_are_named_test() {
  use technique <- list.each(practice.techniques())
  let at = at_the_moment(technique)

  assert tutor.lesson(at, 1).lit == []
  assert tutor.lesson(at, 2).lit == []
  assert tutor.lesson(at, 3).lit != []
  assert tutor.lesson(at, 4).lit != []
}

/// Asking past the bottom says the same thing rather than starting over.
pub fn asking_past_the_bottom_stays_there_test() {
  let at = at_the_moment(logic.NakedPair)

  assert said(at, tutor.rungs) == said(at, tutor.rungs + 5)
}

// ---------------------------------------------------------------------------
// Every technique
// ---------------------------------------------------------------------------

/// The ladder is worked out from the step rather than written down, so it
/// has something to say about all nine — including the three whose argument
/// is not read off a single unit.
pub fn the_moment_is_reachable_on_every_grid_test() {
  let missed = {
    use technique <- list.filter(practice.techniques())
    let at = at_the_moment(technique)
    case logic.next_from(at.board.values, game.reading(at)) {
      Ok(step) -> step.technique != technique
      Error(_) -> True
    }
  }

  assert list.map(missed, logic.label) == []
}

pub fn every_technique_gets_a_whole_ladder_test() {
  use technique <- list.each(practice.techniques())
  let at = at_the_moment(technique)
  let named = string.lowercase(logic.label(technique))

  use asked <- list.each([1, 2, 3, 4])
  let lesson = tutor.lesson(at, asked)

  // Nothing is empty, nothing is a placeholder, and the technique is named
  // at every rung so there is always something to look up.
  assert lesson.what != ""
  assert lesson.why != ""
  assert !string.contains(lesson.what, "nowhere")
  assert !string.contains(lesson.what, "those cells")
  assert string.contains(string.lowercase(lesson.what), named) || asked == 4

  // And both rows fit the two the board has under it. A frame writes each
  // line with a leading space into eighty columns, so seventy-eight is the
  // most there is room for; that a whole frame really fits is asked next
  // door, where frames are what is being looked at.
  assert string.length(lesson.what) <= 78
  assert string.length(lesson.why) <= 78
}

/// Where to look is the one rung that depends on the shape of the argument,
/// and there are four shapes rather than one: a unit for the five read off
/// one, the cell itself for a naked single, which has no unit in it at all,
/// the lines that cross for the two fish, and the pivot for the XY-wing,
/// whose three cells need share nothing.
pub fn where_to_look_suits_the_shape_of_the_argument_test() {
  let unit_shaped = [
    logic.HiddenSingle,
    logic.LockedCandidates,
    logic.NakedPair,
    logic.HiddenPair,
    logic.NakedTriple,
  ]

  use technique <- list.each(unit_shaped)
  let where = tutor.lesson(at_the_moment(technique), 2).what
  assert string.contains(where, "row")
    || string.contains(where, "column")
    || string.contains(where, "box")
}

/// A naked single rests on the one cell and is named by it. There is no
/// nudge short of the answer to be given about a cell that can only be one
/// thing, and pretending otherwise would be a rung that said nothing.
pub fn a_naked_single_is_pointed_at_by_its_cell_test() {
  let at = at_the_moment(logic.NakedSingle)
  let assert Ok(step) = logic.next_from(at.board.values, game.reading(at))
  let assert [only] = step.evidence

  assert string.contains(tutor.lesson(at, 2).what, board.name(only))
}

pub fn a_fish_is_pointed_at_by_its_lines_test() {
  use technique <- list.each([logic.XWing, logic.Swordfish])
  let where = tutor.lesson(at_the_moment(technique), 2).what

  assert string.contains(where, "row")
  assert string.contains(where, "column")
}

pub fn an_xy_wing_is_pointed_at_by_its_pivot_test() {
  let lesson = tutor.lesson(at_the_moment(logic.XYWing), 2)

  assert string.contains(lesson.what, "turns on")
}

// ---------------------------------------------------------------------------
// When it is not the moment
// ---------------------------------------------------------------------------

/// Before the moment it teaches the step that is there, rather than sending
/// somebody away to work it out alone. A grid that wants an X-wing wants a
/// dozen other things on the way to it, and whoever has never seen an X-wing
/// has most likely never seen a hidden pair either.
pub fn before_the_moment_it_teaches_the_step_that_is_there_test() {
  // Fresh, before anything has been taken: the X-wing grid wants a locked
  // candidate first, so that is what it teaches.
  let at = practising(logic.XWing)
  let assert Ok(step) = logic.next_from(at.board.values, game.reading(at))
  assert step.technique == logic.LockedCandidates

  let lesson = tutor.lesson(at, 1)
  assert string.contains(lesson.what, "Locked candidates")
  assert !string.contains(lesson.what, "simpler")

  // And the whole ladder is there for it, the same as for any other step.
  assert string.contains(tutor.lesson(at, 3).what, board.name(first_of(step)))
  assert tutor.lesson(at, 4).what == explained(at).0
}

fn first_of(step: logic.Step) -> Int {
  let assert [cell, ..] = step.evidence
  cell
}

/// The first rung says whether this is the one the grid was kept for, since
/// that is the technique somebody came to meet.
pub fn it_says_when_the_one_you_came_for_arrives_test() {
  let before = tutor.lesson(practising(logic.XWing), 1)
  assert string.contains(before.what, "there is one here")
  assert !string.contains(before.what, "the moment")

  let at = tutor.lesson(at_the_moment(logic.XWing), 1)
  assert string.contains(at.what, "the moment")
}

/// The thing this is for: somebody can be walked from the first step of a
/// grid to the last without ever being told to go away and manage.
pub fn it_guides_a_whole_grid_from_start_to_finish_test() {
  let walked = guided(practising(logic.XWing), 80, [])
  let #(finished, techniques) = walked

  // The grid really was solved, a step at a time, with a lesson at each.
  assert board.empty_count(finished.board) == 0

  // And it took more than one kind of reasoning to get there, which is the
  // whole reason teaching only one of them was not enough.
  assert list.length(list.unique(techniques)) > 1
  assert list.contains(techniques, logic.XWing)
}

/// Every rung has something to say about whatever this step turns out to
/// be, and none of them is the old refusal.
fn has_a_whole_ladder(current: game.Game) -> Nil {
  use asked <- list.each([1, 2, 3, 4])
  let lesson = tutor.lesson(current, asked)

  assert lesson.what != ""
  assert lesson.why != ""
  assert !string.contains(lesson.what, "simpler here")
}

fn guided(
  current: game.Game,
  left: Int,
  seen: List(logic.Technique),
) -> #(game.Game, List(logic.Technique)) {
  case left, logic.next_from(current.board.values, game.reading(current)) {
    0, _ | _, Error(_) -> #(current, seen)
    _, Ok(step) -> {
      has_a_whole_ladder(current)
      guided(game.with_board(current, played(current, step)), left - 1, [
        step.technique,
        ..seen
      ])
    }
  }
}

/// It teaches on any board, not only the nine kept for teaching on. Nothing
/// in a lesson comes from the puzzle — only from the position — so there was
/// never anything for a dealt game to be missing.
pub fn it_teaches_on_an_ordinary_puzzle_too_test() {
  let playing = helper.fixture()
  let assert Ok(step) =
    logic.next_from(playing.board.values, game.reading(playing))

  let lesson = tutor.lesson(playing, 1)
  assert string.contains(
    string.lowercase(lesson.what),
    logic.label(step.technique),
  )

  // With no technique it was kept for, there is no arrival to announce.
  assert !string.contains(lesson.what, "the moment")
  assert string.contains(lesson.what, "there is one here")
}

// ---------------------------------------------------------------------------
// What it costs
// ---------------------------------------------------------------------------

/// The tutor never touches the board, wherever it is asked. That is the
/// whole of why it is worth having beside `H`: `H` plays the step and spends
/// the one chance a practice grid had to teach its technique.
pub fn the_tutor_never_touches_the_board_test() {
  use start <- list.each([at_the_moment(logic.Swordfish), helper.fixture()])
  let assert game.Continue(pressed) = rules.update(start, key.Char("t"))

  assert pressed.board == start.board
  assert pressed.hints == start.hints
}

/// On a practice grid there is nothing to spend, so it costs nothing however
/// often it is asked — which is what makes walking a whole grid with it a
/// thing anybody would do.
pub fn it_costs_nothing_where_nothing_is_at_stake_test() {
  let at = at_the_moment(logic.Swordfish)
  assert !game.at_stake(at)

  let asked =
    list.fold(["t", "t", "t", "t"], at, fn(current, key) {
      let assert game.Continue(next) = rules.update(current, key.Char(key))
      next
    })

  // Asked four times and counted four times — it did happen — but nothing
  // was spent, because a practice grid has nothing to spend.
  assert game.unaided(asked)
  assert asked.tutored == 4
}

// ---------------------------------------------------------------------------
// What it costs on a game that is timed
// ---------------------------------------------------------------------------

/// The same bargain a hint offers, for the same reason. It hands over no
/// digits, but what it hands over is the reasoning the player came to do.
pub fn on_a_timed_game_it_says_what_it_will_cost_first_test() {
  let playing = helper.fixture()
  assert game.at_stake(playing)

  let warned = helper.step(playing, key.Char("t"))
  assert string.contains(warned.message, "aided")
  assert warned.offered == option.Some(game.TakeTutor)

  // Nothing has been spent by being told what it would cost.
  assert game.unaided(warned)
  assert warned.tutored == 0
  assert warned.teaching == game.NotTeaching
}

pub fn pressing_it_again_goes_ahead_test() {
  let taught =
    helper.step(helper.step(helper.fixture(), key.Char("t")), key.Char("t"))

  assert !game.unaided(taught)
  assert taught.tutored == 1
  assert taught.teaching == game.Teaching(1)
  // It played nothing, which is the whole of what it is.
  assert taught.hints == 0
  assert taught.board == helper.fixture().board
}

/// Warned once and not again. Somebody who has spent the timing has nothing
/// left to be warned about.
pub fn the_warning_comes_only_while_there_is_something_to_lose_test() {
  let taught =
    helper.step(helper.step(helper.fixture(), key.Char("t")), key.Char("t"))
  let again = helper.step(taught, key.Char("t"))

  assert again.tutored == 2
  assert again.teaching == game.Teaching(2)
}

/// Asking past the foot of the ladder is not being told anything more, so
/// it is not counted as having been told anything.
pub fn asking_past_the_bottom_costs_nothing_more_test() {
  let walked =
    list.fold(["t", "t", "t", "t", "t", "t", "t"], helper.fixture(), fn(at, _) {
      helper.step(at, key.Char("t"))
    })

  // One press for the warning, four rungs, and two that said nothing new.
  assert walked.tutored == tutor.rungs
}

/// A puzzle typed in is not timed, so there is nothing for the tutor to
/// spend on it — the same as a hint, and for the same reason.
pub fn a_puzzle_typed_in_costs_nothing_test() {
  let typed = helper.playing(helper.puzzle_text)
  assert !game.timed(typed)

  let taught = helper.step(typed, key.Char("t"))

  // No warning, straight to the lesson.
  assert taught.teaching == game.Teaching(1)
  assert game.unaided(taught)
  assert taught.tutored == 1
}
