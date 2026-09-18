//// Puzzles kept to be practised on, one to a technique.
////
//// The help explains each way of working a digit out and draws a small
//// board showing it happening. What it could not do was hand you one to
//// try, and a technique read about and never met is a technique nobody
//// learns: an X-wing turns up in about one dealt Expert puzzle in fifteen,
//// so waiting for one to come round is not a plan.
////
//// Each grid here was carved until the reasoning needed its technique and
//// needed nothing harder, and then given back every clue it could take
//// while that stayed true. So they are the gentlest grids that still force
//// their lesson: the X-wing one has fifty-seven clues and asks for its
//// X-wing on the second step, rather than being a seventeen-clue monster
//// that happens to contain one somewhere.
////
//// They are the same puzzle every time, which is the point — a lesson you
//// can go back to, and compare notes on with somebody else. Nothing is
//// timed and no record is kept of them.

import gleam/list
import gleam/option
import gleam/result
import sudoku/board
import sudoku/generator.{type Puzzle}
import sudoku/logic.{type Technique}

/// The grid kept for each technique, as the 81 characters any of them can be
/// written in. Every one of them has exactly one answer, can be reasoned out
/// without a guess, and is rated at the technique it is filed under — which
/// is a test rather than a promise, since none of that is visible by eye.
pub const grids = [
  #(
    logic.NakedSingle,
    ".12.3..4..78..1.6..4.26.8..18....2.65967.24384.3....91..4.56.2..6.9..38..5..2.67.",
  ),
  #(
    logic.HiddenSingle,
    "837.1.2....43..5...5...63..6..5..87....6.9....73..2..5..12...5...6..47....5.9.683",
  ),
  #(
    logic.LockedCandidates,
    "537981..4.61..59..49..671..7436198..615872439.2...3..1.7..24.18..41...9.1..79.34.",
  ),
  #(
    logic.NakedPair,
    "745198632.9.4768158612534..1..769543..9.4.7..4...8.9..91.63425...48271.....9153.4",
  ),
  #(
    logic.HiddenPair,
    "93521..64...4.9.53.745.312941.3.65.2.6.9..3413..1.46.82..69143..9384521..4.73298.",
  ),
  #(
    logic.NakedTriple,
    "3.8..6...69.8.....12..9.8632.31.96...8634217.41.6.53.27.2.6..188.....256.6.2.873.",
  ),
  #(
    logic.XWing,
    "4239651871.83276...76148.2..1478..622.7.168.968...271..6285.4717.16.42.884.271..6",
  ),
  #(
    logic.XYWing,
    "6..718.29271459.6.98.3627..3569471828.76..9...9.8...765..1.6..7..82.36.5.695.423.",
  ),
  #(
    logic.Swordfish,
    "486217593913..54275279436812947.1.56378596214651.2.....451.2...162.79..5.39.5.1.2",
  ),
]

/// A position to drill a technique on, named rather than written out.
///
/// Three numbers instead of eighty-one characters and a page of marks. A
/// deal is the same deal every time it is asked for, so naming the seed and
/// how far its reasoning had got is naming the position exactly — and a
/// position is what a drill is, since the candidates are half of it and a
/// grid alone cannot carry those.
pub type Drill {
  Drill(difficulty: generator.Difficulty, seed: Int, taken: Int)
}

/// Positions where each technique is the step that comes next.
///
/// The grid above gives one instance of its technique and never another —
/// it is the same grid every time, so a second run at it is remembering
/// rather than seeing. These are for after that: a different position every
/// time, all of them out of real deals, each of them at the moment.
///
/// Found by dealing and watching where the reasoning reached for each. The
/// harder ones had to be hunted for, a swordfish turning up about once in
/// twenty-five Master deals.
pub const drills = [
  #(
    logic.NakedSingle,
    [
      Drill(generator.Hard, 7919, 15),
      Drill(generator.Hard, 15_838, 18),
      Drill(generator.Hard, 23_757, 13),
      Drill(generator.Hard, 31_676, 11),
    ],
  ),
  #(
    logic.HiddenSingle,
    [
      Drill(generator.Expert, 7919, 1),
      Drill(generator.Expert, 15_838, 1),
      Drill(generator.Expert, 39_595, 8),
      Drill(generator.Master, 237_570, 25),
    ],
  ),
  #(
    logic.LockedCandidates,
    [
      Drill(generator.Hard, 7919, 20),
      Drill(generator.Hard, 15_838, 17),
      Drill(generator.Hard, 23_757, 12),
      Drill(generator.Hard, 31_676, 7),
    ],
  ),
  #(
    logic.NakedPair,
    [
      Drill(generator.Expert, 15_838, 6),
      Drill(generator.Expert, 39_595, 21),
      Drill(generator.Expert, 47_514, 11),
      Drill(generator.Expert, 71_271, 14),
    ],
  ),
  #(
    logic.HiddenPair,
    [
      Drill(generator.Expert, 7919, 18),
      Drill(generator.Expert, 23_757, 11),
      Drill(generator.Expert, 31_676, 9),
      Drill(generator.Expert, 55_433, 11),
    ],
  ),
  #(
    logic.NakedTriple,
    [
      Drill(generator.Expert, 134_623, 19),
      Drill(generator.Expert, 467_221, 16),
      Drill(generator.Master, 277_165, 23),
      Drill(generator.Master, 498_897, 24),
    ],
  ),
  #(
    logic.XWing,
    [
      Drill(generator.Expert, 150_461, 16),
      Drill(generator.Expert, 182_137, 27),
      Drill(generator.Expert, 300_922, 26),
      Drill(generator.Expert, 324_679, 18),
    ],
  ),
  #(
    logic.XYWing,
    [
      Drill(generator.Master, 7919, 45),
      Drill(generator.Master, 15_838, 32),
      Drill(generator.Master, 23_757, 37),
      Drill(generator.Master, 39_595, 28),
    ],
  ),
  #(
    logic.Swordfish,
    [
      Drill(generator.Master, 229_651, 15),
      Drill(generator.Master, 554_330, 27),
      Drill(generator.Master, 768_143, 23),
    ],
  ),
]

pub fn drills_for(technique: Technique) -> List(Drill) {
  list.key_find(drills, technique) |> result.unwrap([])
}

/// The puzzle a drill names: the board as the reasoning had left it, the
/// marks with it, and the answer it is all heading for.
///
/// The cells already filled become clues. They are all right — the
/// reasoning put them there — and a drill is not the place to be taking
/// back somebody else's working.
///
/// Told as it goes, because getting back to a position means dealing the
/// puzzle it came out of, and a Master deal takes a second or two.
pub fn drilled(
  technique: Technique,
  drill: Drill,
  telling: fn(generator.Carving) -> Nil,
) -> Puzzle {
  let dealt = generator.generate_telling(drill.seed, drill.difficulty, telling)
  let #(grid, marks) = logic.unfolded(dealt.board.values, drill.taken)
  let stood = board.from_grid(grid)

  generator.Puzzle(
    board: board.Board(..stood, marks: marks),
    solution: dealt.solution,
    origin: generator.Practising(technique),
    seed: option.None,
  )
}

/// The number the menu offers practice under: the one after the puzzles
/// there are to deal, whatever those turn out to be.
pub fn choice() -> Int {
  list.length(generator.origins()) + 1
}

/// The techniques there is a puzzle for, easiest first — which is every one
/// of them, in the order the help pages them.
pub fn techniques() -> List(Technique) {
  list.map(grids, fn(kept) { kept.0 })
}

/// The puzzle kept for practising this technique.
///
/// Solved on the way out, the same as a puzzle typed in by hand, rather than
/// having its answer written down beside it here. The answer is not the
/// interesting part of a grid and would be eighty-one more characters to get
/// wrong by hand.
pub fn puzzle(technique: Technique) -> Result(Puzzle, Nil) {
  use clues <- result.try(list.key_find(grids, technique))
  use grid <- result.try(board.parse(clues))

  generator.made_of(grid, generator.Practising(technique))
  |> result.replace_error(Nil)
}

/// How many clues the grid for a technique is dealt with, for the screen
/// offering them to say how much of a puzzle each one is.
pub fn clue_count(technique: Technique) -> Int {
  case list.key_find(grids, technique) |> result.try(board.parse) {
    Error(_) -> 0
    Ok(grid) -> board.cell_count - board.empty_count(board.from_grid(grid))
  }
}
