//// The puzzle of the day: which day it is, how hard that makes it, and what
//// the book of days makes of a time.

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import helper
import sudoku/board
import sudoku/date
import sudoku/game
import sudoku/generator
import sudoku/invocation
import sudoku/logic
import sudoku/store

fn on(text: String) -> date.Date {
  let assert Ok(day) = date.parse(text)
  day
}

// ---------------------------------------------------------------------------
// Days
// ---------------------------------------------------------------------------

pub fn a_date_is_written_the_one_unambiguous_way_test() {
  assert date.to_string(date.Date(2026, 9, 17)) == "2026-09-17"
  // Padded, so that every date is the same width and sorts as it reads.
  assert date.to_string(date.Date(999, 1, 2)) == "0999-01-02"
}

pub fn a_date_read_back_is_the_date_written_test() {
  use written <- list.each(["2026-09-17", "2024-02-29", "0001-01-01"])
  let assert Ok(day) = date.parse(written)
  assert date.to_string(day) == written
}

/// A day that never happened would deal a puzzle nobody else could ever be
/// handed, which is the one thing a daily must not do.
pub fn a_day_that_did_not_happen_is_refused_test() {
  use written <- list.each([
    "2026-02-30",
    "2025-02-29",
    "2026-13-01",
    "2026-09-32",
    "2026-00-01",
    "2026-9",
    "17-09-2026",
    "yesterday",
    "",
  ])
  assert date.parse(written) == Error(Nil)
}

pub fn the_week_runs_monday_to_sunday_test() {
  // The 14th of September 2026 was a Monday.
  let week = [
    #("2026-09-14", date.Monday),
    #("2026-09-15", date.Tuesday),
    #("2026-09-16", date.Wednesday),
    #("2026-09-17", date.Thursday),
    #("2026-09-18", date.Friday),
    #("2026-09-19", date.Saturday),
    #("2026-09-20", date.Sunday),
  ]

  use #(written, day) <- list.each(week)
  assert date.weekday(on(written)) == day
}

// ---------------------------------------------------------------------------
// How hard a day is
// ---------------------------------------------------------------------------

/// The week ramps and everybody gets the same ramp, which is the point: two
/// people who have never met are handed the same grid, so neither of them
/// can be asked which difficulty they fancied.
pub fn the_week_ramps_from_monday_test() {
  let week = [
    #("2026-09-14", generator.Easy),
    #("2026-09-15", generator.Easy),
    #("2026-09-16", generator.Medium),
    #("2026-09-17", generator.Medium),
    #("2026-09-18", generator.Hard),
    #("2026-09-19", generator.Expert),
    #("2026-09-20", generator.Master),
  ]

  use #(written, difficulty) <- list.each(week)
  assert generator.daily_difficulty(on(written)) == difficulty
}

/// Every difficulty turns up in a week, so nobody who plays the daily and
/// nothing else is kept away from a level.
pub fn a_week_holds_every_difficulty_test() {
  let week = {
    use day <- list.map([
      "2026-09-14",
      "2026-09-15",
      "2026-09-16",
      "2026-09-17",
      "2026-09-18",
      "2026-09-19",
      "2026-09-20",
    ])
    generator.daily_difficulty(on(day))
  }

  use difficulty <- list.each(generator.difficulties)
  assert list.contains(week, difficulty)
}

pub fn the_seed_of_a_day_is_the_day_read_as_a_number_test() {
  assert generator.daily_seed(on("2026-09-17")) == 20_260_917
  assert generator.daily_seed(on("0001-01-01")) == 10_101
}

// ---------------------------------------------------------------------------
// The puzzle itself
// ---------------------------------------------------------------------------

/// Dealt at Easy, a Monday, because this is the slowest test here and a
/// Sunday takes a second over it. What is being tested is that the day
/// steers the deal, and it steers every day the same way.
pub fn a_day_deals_the_same_puzzle_every_time_test() {
  let once = generator.deal_daily(on("2026-09-14"), fn(_) { Nil })
  let again = generator.deal_daily(on("2026-09-14"), fn(_) { Nil })

  assert once.board.values == again.board.values
  assert once.solution == again.solution
}

pub fn different_days_deal_different_puzzles_test() {
  let monday = generator.deal_daily(on("2026-09-14"), fn(_) { Nil })
  let tuesday = generator.deal_daily(on("2026-09-15"), fn(_) { Nil })

  assert monday.board.values != tuesday.board.values
}

pub fn a_daily_knows_which_day_it_belongs_to_test() {
  let monday = generator.deal_daily(on("2026-09-14"), fn(_) { Nil })

  assert monday.origin == generator.Daily(on("2026-09-14"))
  assert monday.seed == Some(generator.daily_seed(on("2026-09-14")))

  // And is a proper puzzle on the same terms as any other deal.
  assert board.is_consistent(monday.board.values)
  assert board.is_solved(board.from_grid(monday.solution))
  assert logic.rate(monday.board.values) != Error(Nil)
}

// ---------------------------------------------------------------------------
// The book of days
// ---------------------------------------------------------------------------

fn daily_game(written: String) -> game.Game {
  let played = helper.fixture()
  game.Game(
    ..played,
    puzzle: generator.Puzzle(
      ..played.puzzle,
      origin: generator.Daily(on(written)),
    ),
  )
}

pub fn a_day_done_for_the_first_time_is_written_down_test() {
  let won = helper.solved(daily_game("2026-09-17"))

  assert game.unaided(won)
  assert store.judge(won, dict.new(), dict.new()) == game.DailyDone
}

/// The first run at a day is the one kept. A day played again is a day whose
/// answer is already known, so a quicker second run is not a quicker solve —
/// and the book says what you did on the day rather than what you did once
/// you had seen it.
pub fn a_day_already_done_keeps_its_first_time_test() {
  let won = helper.solved(daily_game("2026-09-17"))
  let book = dict.from_list([#(on("2026-09-17"), 245_000)])

  assert store.judge(won, dict.new(), book) == game.DailyAlready(245_000)

  // Another day's time in the book is another day's business.
  let elsewhere = dict.from_list([#(on("2026-09-16"), 245_000)])
  assert store.judge(won, dict.new(), elsewhere) == game.DailyDone
}

pub fn a_day_solved_with_help_is_not_written_down_test() {
  let helped = helper.solved(helper.checked(daily_game("2026-09-17")))

  assert !game.unaided(helped)
  assert store.judge(helped, dict.new(), dict.new()) == game.Aided
}

pub fn a_day_not_won_is_not_written_down_test() {
  assert store.judge(daily_game("2026-09-17"), dict.new(), dict.new())
    == game.Untimed
}

/// The two books are separate on purpose: a best is the quickest of many
/// puzzles at a level and goes on being beaten, and a day is one puzzle that
/// happened once. A day done quickly should not turn up as a Medium record
/// nobody can find the puzzle for.
pub fn a_day_does_not_touch_the_difficulty_bests_test() {
  let won = helper.solved(daily_game("2026-09-17"))
  let bests = dict.from_list([#(generator.Medium, 1)])

  // An unbeatable Medium best standing does not make the day Behind.
  assert store.judge(won, bests, dict.new()) == game.DailyDone
}

// ---------------------------------------------------------------------------
// Putting one down and picking it up
// ---------------------------------------------------------------------------

pub fn a_daily_put_down_comes_back_as_the_same_day_test() {
  let played = daily_game("2026-09-17")
  let assert Ok(back) = store.decode(store.encode(played))

  assert back.puzzle.origin == generator.Daily(on("2026-09-17"))
}

/// The difficulty is worked out from the date rather than written beside it,
/// so a file cannot come back disagreeing with itself about what day it is
/// for.
pub fn a_saved_daily_keeps_only_the_day_test() {
  let written = store.encode(daily_game("2026-09-20"))

  assert list.contains(string.split(written, "\n"), "origin daily 2026-09-20")
  assert generator.origin_label(generator.Daily(on("2026-09-20")))
    == "Daily Master"
}

// ---------------------------------------------------------------------------
// Asking for one
// ---------------------------------------------------------------------------

pub fn the_command_line_takes_daily_on_its_own_test() {
  assert invocation.read(["daily"])
    == Ok(invocation.Invocation(invocation.Today, False, None))

  // However it is capitalised, the way every other word on the line is.
  assert invocation.read(["DAILY"])
    == Ok(invocation.Invocation(invocation.Today, False, None))
}

pub fn the_command_line_takes_a_day_by_name_test() {
  assert invocation.read(["daily", "2026-09-17"])
    == Ok(invocation.Invocation(invocation.Day(on("2026-09-17")), False, None))

  // Beside the flag that says how it should look.
  assert invocation.read(["--plain", "daily", "2026-09-17"])
    == Ok(invocation.Invocation(invocation.Day(on("2026-09-17")), True, None))
}

pub fn a_day_that_will_not_read_is_refused_by_name_test() {
  let assert Error(complaint) = invocation.read(["daily", "2026-02-30"])

  assert !string.contains(complaint, "Usage:")
  assert string.contains(complaint, "2026-02-30")
}

/// A daily is carved from its date. A seed beside it would have to be
/// ignored, and ignoring it quietly is how somebody comes to believe they
/// are playing a puzzle they are not.
pub fn a_daily_will_not_take_a_seed_test() {
  use line <- list.each([
    ["daily", "--seed", "42"],
    ["daily", "2026-09-17", "--seed", "42"],
  ])
  let assert Error(complaint) = invocation.read(line)
  assert string.contains(complaint, invocation.seed_flag)
}

/// The book goes out as text and comes back as the same book. Kept apart
/// from the file it lands in, so this can be asked without a disk to hand.
pub fn the_book_of_days_survives_being_written_down_test() {
  let book =
    dict.from_list([
      #(on("2026-09-17"), 245_000),
      #(on("2026-09-14"), 61_000),
      #(on("2026-09-20"), 3_600_000),
    ])

  assert store.dailies_read(store.dailies_written(book)) == book

  // Oldest first, which is the order somebody reading the file would have
  // put it in.
  assert store.dailies_written(book)
    == "2026-09-14 61000\n2026-09-17 245000\n2026-09-20 3600000"
}

/// A line that will not read costs one day rather than the whole book. This
/// is a file a person is invited to open, and a stray keystroke in it should
/// not throw away a month of mornings.
pub fn a_spoiled_line_costs_only_its_own_day_test() {
  let book =
    store.dailies_read(
      "2026-09-14 61000\nrubbish\n2026-02-30 1000\n2026-09-17 245000\n\n",
    )

  assert dict.get(book, on("2026-09-14")) == Ok(61_000)
  assert dict.get(book, on("2026-09-17")) == Ok(245_000)
  assert dict.size(book) == 2
}

pub fn an_empty_book_is_a_book_with_no_days_in_it_test() {
  assert store.dailies_read("") == dict.new()
}
