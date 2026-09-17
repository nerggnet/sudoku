//// A date, which is as much of a calendar as this game needs: the day a
//// puzzle belongs to, and which day of the week that was.
////
//// Kept apart from everything that uses it. What day it is is a question
//// about the world, and how hard a puzzle should be on a Thursday is a
//// question about Sudoku; the second one is next door in `generator`, which
//// knows about difficulties. This knows about days.

import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type Date {
  Date(year: Int, month: Int, day: Int)
}

/// Today, where the player is.
pub fn today() -> Date {
  let #(year, month, day) = today_parts()
  Date(year:, month:, day:)
}

/// Written the one way a date can be written without anybody having to know
/// which half of the world wrote it: `2026-09-17`.
///
/// It is also what the command line takes, so a date on the screen is a date
/// somebody can type back in — which is the whole of how two people end up
/// playing the same grid.
pub fn to_string(date: Date) -> String {
  padded(date.year, 4)
  <> "-"
  <> padded(date.month, 2)
  <> "-"
  <> padded(date.day, 2)
}

fn padded(number: Int, width: Int) -> String {
  string.pad_start(int.to_string(number), width, "0")
}

/// Read a date back, or refuse it.
///
/// Three numbers with dashes between them, and a day that really happened:
/// the 30th of February is a typing slip rather than a date, and a puzzle
/// dealt for it would be a puzzle nobody else could ever be handed.
pub fn parse(text: String) -> Result(Date, Nil) {
  use #(year, month, day) <- result.try(case string.split(text, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) -> Ok(#(year, month, day))
        _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  })

  case is_valid(year, month, day) {
    True -> Ok(Date(year:, month:, day:))
    False -> Error(Nil)
  }
}

pub type Day {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

/// The days, in the order the week runs.
pub const days = [
  Monday,
  Tuesday,
  Wednesday,
  Thursday,
  Friday,
  Saturday,
  Sunday,
]

pub fn weekday(date: Date) -> Day {
  // The calendar counts Monday as 1, and the list starts at nothing.
  case list.drop(days, day_of_week(date.year, date.month, date.day) - 1) {
    [day, ..] -> day
    // Not reachable with a date that parsed, every one of which falls on a
    // day. Monday is as good an answer as any for one that did not.
    [] -> Monday
  }
}

pub fn day_name(day: Day) -> String {
  case day {
    Monday -> "Monday"
    Tuesday -> "Tuesday"
    Wednesday -> "Wednesday"
    Thursday -> "Thursday"
    Friday -> "Friday"
    Saturday -> "Saturday"
    Sunday -> "Sunday"
  }
}

@external(erlang, "sudoku_ffi", "today")
fn today_parts() -> #(Int, Int, Int)

@external(erlang, "sudoku_ffi", "day_of_week")
fn day_of_week(year: Int, month: Int, day: Int) -> Int

@external(erlang, "sudoku_ffi", "valid_date")
fn is_valid(year: Int, month: Int, day: Int) -> Bool
