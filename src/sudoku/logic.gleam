//// Solving a grid the way a person does.
////
//// The search in `sudoku/solver` answers whether a grid has an answer and
//// what it is. This answers a different question: how the answer can be
//// reasoned out, a step at a time, and how hard that reasoning has to get.
//// That is what rates a puzzle, and what a hint needs before it can say
//// anything more useful than a digit.
////
//// Techniques are tried easiest first, so the step offered is always the
//// simplest one going, and the hardest technique a grid calls for before it
//// gives up its answer is what the grid is rated by.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string
import sudoku/board.{type Grid}

/// The ways a cell can be argued into giving up its digit, easiest first.
pub type Technique {
  /// One candidate left in a cell.
  NakedSingle
  /// One cell left in a unit that can take a digit.
  HiddenSingle
  /// A digit shut into the crossing of a box and a line.
  LockedCandidates
  /// Two cells in a unit between them holding two digits.
  NakedPair
  /// Two digits in a unit between them holding two cells.
  HiddenPair
  /// Three cells in a unit between them holding three digits.
  NakedTriple
  /// A digit down to the same two columns in two rows, or the other way
  /// about.
  XWing
  /// Three cells of two candidates apiece, hinged on one that sees the other
  /// two, which between them leave a digit nowhere to hide.
  XYWing
  /// The same argument as an X-wing over three lines instead of two.
  Swordfish
}

/// Every technique, easiest first.
pub const techniques = [
  NakedSingle,
  HiddenSingle,
  LockedCandidates,
  NakedPair,
  HiddenPair,
  NakedTriple,
  XWing,
  XYWing,
  Swordfish,
]

pub fn label(technique: Technique) -> String {
  case technique {
    NakedSingle -> "naked single"
    HiddenSingle -> "hidden single"
    LockedCandidates -> "locked candidates"
    NakedPair -> "naked pair"
    HiddenPair -> "hidden pair"
    NakedTriple -> "naked triple"
    XWing -> "X-wing"
    XYWing -> "XY-wing"
    Swordfish -> "swordfish"
  }
}

/// The technique's name, as several of them. Not every name takes an `s`.
pub fn labels(technique: Technique) -> String {
  case technique {
    NakedSingle -> "naked singles"
    HiddenSingle -> "hidden singles"
    LockedCandidates -> "locked candidates"
    NakedPair -> "naked pairs"
    HiddenPair -> "hidden pairs"
    NakedTriple -> "naked triples"
    XWing -> "X-wings"
    XYWing -> "XY-wings"
    Swordfish -> "swordfish"
  }
}

/// The technique going by this name, however it is capitalised. The inverse
/// of `label`, for a saved game to say which one it was kept for.
pub fn named(name: String) -> Result(Technique, Nil) {
  use technique <- list.find(techniques)
  string.lowercase(label(technique)) == string.lowercase(name)
}

/// How hard a technique is, counting from nothing. Which of two techniques
/// is the harder is which of these is the greater.
pub fn rank(technique: Technique) -> Int {
  case technique {
    NakedSingle -> 0
    HiddenSingle -> 1
    LockedCandidates -> 2
    NakedPair -> 3
    HiddenPair -> 4
    NakedTriple -> 5
    XWing -> 6
    XYWing -> 7
    Swordfish -> 8
  }
}

/// What a step does to the grid.
pub type Move {
  /// The digit belongs in the cell, and nothing else does.
  Settle(index: Int, digit: Int)
  /// The digits cannot go in any of these cells, though what does is still
  /// an open question.
  RuleOut(cells: List(Int), digits: List(Int))
}

/// A single move; the cells the reasoning behind it rests on — the unit a
/// hidden single is hidden in, the pair a naked pair is made of, the four
/// corners of an X-wing; and the digits it is about.
///
/// What a step is about is not always what it rules out. A hidden pair rules
/// out everything except the two digits it is about, and those two are what
/// there is to say about it.
pub type Step {
  Step(
    technique: Technique,
    move: Move,
    evidence: List(Int),
    about: List(Int),
    /// The unit the argument was made in, where it was made in one. Two or
    /// three cells can share a row and a box at once, so which unit a
    /// technique was reading cannot be recovered from them afterwards — it
    /// has to be carried.
    unit: List(Int),
  )
}

/// What every empty cell could still hold. Cells already filled are absent
/// rather than empty, so a cell is open exactly when it has an entry.
pub type Pencil =
  Dict(Int, Set(Int))

/// The candidates a grid starts out with.
pub fn pencil(grid: Grid) -> Pencil {
  let peers = board.peers_table()

  use marks, index <- list.fold(board.indices(), dict.new())
  case dict.get(grid, index) {
    Ok(0) | Error(_) ->
      dict.insert(
        marks,
        index,
        set.from_list(board.candidates(grid, peers, index)),
      )
    Ok(_) -> marks
  }
}

// ---------------------------------------------------------------------------
// Working through a grid
// ---------------------------------------------------------------------------

/// Reason a grid out as far as reasoning goes, returning every step taken in
/// the order they were taken, and the grid they left behind.
pub fn unfold(grid: Grid) -> #(List(Step), Grid) {
  work(grid, pencil(grid), [])
}

/// The position a grid is in after the first `taken` steps of reasoning:
/// what is on it, and what its cells have left in them.
///
/// The candidates are the point. A grid alone cannot say what has been ruled
/// out of it — an elimination leaves no mark on the digits — so a position
/// part way through an argument is only a position if it carries both, and
/// is only reachable by walking there from the start.
pub fn unfolded(grid: Grid, taken: Int) -> #(Grid, Pencil) {
  walked(grid, pencil(grid), taken)
}

fn walked(grid: Grid, marks: Pencil, left: Int) -> #(Grid, Pencil) {
  case left, step(grid, marks) {
    0, _ | _, Error(_) -> #(grid, marks)
    _, Ok(found) -> {
      let #(grid, marks) = apply(grid, marks, found)
      walked(grid, marks, left - 1)
    }
  }
}

fn work(grid: Grid, marks: Pencil, taken: List(Step)) -> #(List(Step), Grid) {
  case step(grid, marks) {
    Error(_) -> #(list.reverse(taken), grid)
    Ok(found) -> {
      let #(grid, marks) = apply(grid, marks, found)
      work(grid, marks, [found, ..taken])
    }
  }
}

/// The simplest step a grid will give up, which is what a hint should offer.
pub fn next(grid: Grid) -> Result(Step, Nil) {
  next_from(grid, pencil(grid))
}

/// The same from candidates that have been narrowed by hand.
///
/// A player's marks are a position of their own: narrower than the grid alone
/// allows wherever they have been working, and the only place a step that
/// rules candidates out leaves a trace. Reasoning from them is what lets one
/// such step lead to the next.
pub fn next_from(grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  step(grid, marks)
}

/// The simplest step that settles one particular cell, if what is on the
/// board settles it at all.
///
/// Only two techniques settle a cell rather than ruling candidates out, so
/// these two are the whole of what can be said about a cell on its own. The
/// rest is said about a unit, and belongs to whatever `next` makes of it.
pub fn settles(grid: Grid, index: Int) -> Result(Step, Nil) {
  settles_from(pencil(grid), index)
}

/// The same from candidates narrowed by hand.
pub fn settles_from(marks: Pencil, index: Int) -> Result(Step, Nil) {
  case candidates(marks, index) {
    [] -> Error(Nil)
    [digit] -> Ok(Step(NakedSingle, Settle(index, digit), [index], [digit], []))
    digits -> only_home(marks, index, digits)
  }
}

/// Whether any of the cell's candidates has nowhere else to go in one of the
/// three units the cell belongs to.
fn only_home(
  marks: Pencil,
  index: Int,
  digits: List(Int),
) -> Result(Step, Nil) {
  use unit <- list.find_map(list.filter(board.units(), list.contains(_, index)))
  use digit <- list.find_map(digits)

  case holding(marks, unit, digit) {
    [only] ->
      case only == index {
        True ->
          Ok(Step(HiddenSingle, Settle(index, digit), [index], [digit], unit))
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// The hardest technique a grid needs before it gives up its answer, or
/// `Error` where reasoning alone does not get there.
///
/// A grid that is already full asked nothing of anybody, and is rated as
/// easily as a grid can be.
pub fn rate(grid: Grid) -> Result(Technique, Nil) {
  let #(steps, reasoned) = unfold(grid)

  case board.empty_count(board.from_grid(reasoned)) {
    0 -> Ok(hardest(steps))
    _ -> Error(Nil)
  }
}

fn hardest(steps: List(Step)) -> Technique {
  use hardest, step <- list.fold(steps, NakedSingle)
  case rank(step.technique) > rank(hardest) {
    True -> step.technique
    False -> hardest
  }
}

/// Try the techniques in turn and take the first step going.
fn step(grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  first_of(
    [
      naked_single,
      hidden_single,
      locked_candidates,
      naked_pair,
      hidden_pair,
      naked_triple,
      x_wing,
      xy_wing,
      swordfish,
    ],
    grid,
    marks,
  )
}

fn first_of(
  finders: List(fn(Grid, Pencil) -> Result(Step, Nil)),
  grid: Grid,
  marks: Pencil,
) -> Result(Step, Nil) {
  case finders {
    [] -> Error(Nil)
    [find, ..rest] ->
      case find(grid, marks) {
        Ok(step) -> Ok(step)
        Error(_) -> first_of(rest, grid, marks)
      }
  }
}

/// Write a step into the grid and the candidates alike.
fn apply(grid: Grid, marks: Pencil, step: Step) -> #(Grid, Pencil) {
  case step.move {
    Settle(index, digit) -> #(
      dict.insert(grid, index, digit),
      marks
        |> dict.delete(index)
        |> forget(board.peers_of(index), [digit]),
    )
    RuleOut(cells, digits) -> #(grid, forget(marks, cells, digits))
  }
}

fn forget(marks: Pencil, cells: List(Int), digits: List(Int)) -> Pencil {
  use marks, index <- list.fold(cells, marks)
  use marks, digit <- list.fold(digits, marks)
  case dict.get(marks, index) {
    Error(_) -> marks
    Ok(left) -> dict.insert(marks, index, set.delete(left, digit))
  }
}

// ---------------------------------------------------------------------------
// Saying it out loud
// ---------------------------------------------------------------------------

/// A step, put the way a person would put it, and named.
///
/// The name comes first because the name is the part worth keeping. A player
/// told that C8 and F8 take 7 and 8 between them has been given this move;
/// one told that it is a naked pair has been given every naked pair they will
/// ever meet, and something to look up besides.
///
/// What follows the name is the crux of it rather than the whole argument.
/// The consequence — the digit going in, the marks coming out — happens on
/// the screen as it is said, and the name is there for the rest.
pub fn explain(step: Step) -> #(String, String) {
  #(title(step.technique) <> ": " <> crux(step), because(step))
}

/// The line under the first: why the crux settles it, and what has just
/// changed on the board because it does.
///
/// One clause, and never the working in full. A hint nobody reads to the end
/// of has explained nothing.
fn because(step: Step) -> String {
  case step.technique, step.move {
    NakedSingle, Settle(_, _) ->
      "Every other digit is already in its row, column or box."

    HiddenSingle, Settle(_, digit) ->
      "The other empty cells in "
      <> unit_name(step.unit)
      <> " can all see a "
      <> int.to_string(digit)
      <> " already."

    LockedCandidates, RuleOut(cells, _) ->
      "So no "
      <> written(step.about)
      <> " anywhere else in "
      <> unit_name(step.unit)
      <> " — "
      <> these(cells)
      <> " "
      <> lose(cells)
      <> " it."

    NakedPair, RuleOut(cells, _) ->
      "One each, whichever way round, so "
      <> these(cells)
      <> " "
      <> lose(cells)
      <> " both."

    NakedTriple, RuleOut(cells, _) ->
      "One each, so " <> these(cells) <> " " <> lose(cells) <> " all three."

    HiddenPair, RuleOut(_, _) ->
      "One each, so nothing else fits in either of them."

    XWing, RuleOut(cells, _) | Swordfish, RuleOut(cells, _) -> {
      let #(base, cover) = case reads_across(step) {
        True -> #("row", "column")
        False -> #("column", "row")
      }

      "One in each "
      <> base
      <> " means one in each "
      <> cover
      <> ", so "
      <> these(cells)
      <> " "
      <> lose(cells)
      <> " it."
    }

    XYWing, RuleOut(cells, _) ->
      "So nothing that can see both of them can be "
      <> a_digit(step.about)
      <> " — "
      <> these(cells)
      <> " "
      <> lose(cells)
      <> " it."

    _, _ -> ""
  }
}

/// Which way the rectangle was read: whether the eliminations landed in the
/// columns its corners sit in, or in the rows.
fn reads_across(step: Step) -> Bool {
  let columns = list.map(step.evidence, board.col_of)
  case step.move {
    Settle(_, _) -> True
    RuleOut(cells, _) ->
      list.all(cells, fn(index) { list.contains(columns, board.col_of(index)) })
  }
}

/// One cell loses a candidate; several lose theirs.
fn lose(cells: List(Int)) -> String {
  case cells {
    [_] -> "loses"
    _ -> "lose"
  }
}

/// Cells by name while there are few enough for names to help, and by the
/// count of them once there are not.
fn these(cells: List(Int)) -> String {
  case list.length(cells) {
    few if few <= 3 -> cell_names(cells)
    many -> int.to_string(many) <> " cells"
  }
}

fn title(technique: Technique) -> String {
  let name = label(technique)
  string.uppercase(string.slice(name, 0, 1))
  <> string.slice(name, 1, string.length(name) - 1)
}

fn crux(step: Step) -> String {
  case step.technique, step.move {
    NakedSingle, Settle(index, digit) ->
      board.name(index) <> " can only be a " <> int.to_string(digit) <> "."

    HiddenSingle, Settle(index, digit) ->
      board.name(index)
      <> " is the only cell in "
      <> unit_name(step.unit)
      <> " that can take a "
      <> int.to_string(digit)
      <> "."

    // The digit is shut into the crossing of two units, so both get named.
    LockedCandidates, RuleOut(_, _) ->
      "every "
      <> written(step.about)
      <> " in "
      <> crossing_of(step.evidence, step.unit)
      <> " is in "
      <> unit_name(step.unit)
      <> "."

    NakedPair, RuleOut(_, _) | NakedTriple, RuleOut(_, _) ->
      cell_names(step.evidence)
      <> " take "
      <> written(step.about)
      <> " between them."

    HiddenPair, RuleOut(_, _) ->
      "only "
      <> cell_names(step.evidence)
      <> " can take "
      <> either(step.about)
      <> " in their "
      <> unit_kind(step.unit)
      <> "."

    XWing, RuleOut(_, _) | Swordfish, RuleOut(_, _) -> {
      let #(base, cover) = case reads_across(step) {
        True -> #(rows_of(step.evidence), columns_of(step.evidence))
        False -> #(columns_of(step.evidence), rows_of(step.evidence))
      }

      a_digit(step.about) <> " in " <> base <> " keeps to " <> cover <> "."
    }

    // The pivot first, since it is the cell the argument turns on and the
    // one to look at: the wings are what follow from it.
    XYWing, RuleOut(_, _) ->
      case step.evidence {
        [pivot, one, other] ->
          "whichever way "
          <> board.name(pivot)
          <> " falls, one of "
          <> cell_names([one, other])
          <> " is "
          <> a_digit(step.about)
          <> "."
        _ -> ""
      }

    // Every technique has its own words above; this is only reached if one
    // is added without them.
    _, Settle(index, digit) ->
      board.name(index) <> " is a " <> int.to_string(digit) <> "."
    _, RuleOut(cells, digits) ->
      "no " <> written(digits) <> " in " <> cell_names(cells) <> "."
  }
}

/// The unit the cells all sit in, named the way the player sees it.
fn unit_name(cells: List(Int)) -> String {
  case
    all_alike(cells, board.row_of),
    all_alike(cells, board.col_of),
    all_alike(cells, board.box_of)
  {
    Ok(_), _, _ -> name_of(cells, board.row_name)
    _, Ok(_), _ -> name_of(cells, board.column_name)
    _, _, Ok(_) -> name_of(cells, board.box_name)
    _, _, _ -> cell_names(cells)
  }
}

/// Cells shut into the crossing of a box and a line sit in both at once. The
/// one to name is whichever kind the eliminations did not land in.
fn crossing_of(cells: List(Int), unit: List(Int)) -> String {
  case unit_kind(unit) {
    "box" ->
      case all_alike(cells, board.row_of) {
        Ok(_) -> name_of(cells, board.row_name)
        Error(_) -> name_of(cells, board.column_name)
      }
    _ -> name_of(cells, board.box_name)
  }
}

/// Whether a unit is a row, a column or a box.
fn unit_kind(unit: List(Int)) -> String {
  case all_alike(unit, board.row_of), all_alike(unit, board.col_of) {
    Ok(_), _ -> "row"
    _, Ok(_) -> "column"
    _, _ -> "box"
  }
}

fn name_of(cells: List(Int), naming: fn(Int) -> String) -> String {
  case cells {
    [first, ..] -> naming(first)
    [] -> "nowhere"
  }
}

fn rows_of(cells: List(Int)) -> String {
  cells
  |> list.map(board.row_of)
  |> spread
  |> list.map(board.row_letter)
  |> plural("row", _)
}

fn columns_of(cells: List(Int)) -> String {
  cells
  |> list.map(board.col_of)
  |> spread
  |> list.map(fn(column) { int.to_string(column + 1) })
  |> plural("column", _)
}

fn spread(values: List(Int)) -> List(Int) {
  values |> list.unique |> list.sort(int.compare)
}

fn plural(what: String, names: List(String)) -> String {
  case names {
    [one] -> what <> " " <> one
    _ -> what <> "s " <> joined(names, "and")
  }
}

fn cell_names(cells: List(Int)) -> String {
  cells |> list.map(board.name) |> joined("and")
}

/// A digit with the article that goes in front of it. Eight is the one that
/// takes `an`, said aloud as a digit rather than as a word.
fn a_digit(digits: List(Int)) -> String {
  let said = written(digits)
  case string.starts_with(said, "8") {
    True -> "an " <> said
    False -> "a " <> said
  }
}

fn written(digits: List(Int)) -> String {
  digits |> spread |> list.map(int.to_string) |> joined("and")
}

fn either(digits: List(Int)) -> String {
  digits |> spread |> list.map(int.to_string) |> joined("or")
}

/// `A1`, `A1 and B2`, `A1, B2 and C3`.
fn joined(words: List(String), last_word: String) -> String {
  case list.reverse(words) {
    [] -> "nothing"
    [only] -> only
    [last, ..rest] ->
      { rest |> list.reverse |> string.join(", ") }
      <> " "
      <> last_word
      <> " "
      <> last
  }
}

// ---------------------------------------------------------------------------
// The techniques
// ---------------------------------------------------------------------------

/// A cell with one candidate left has to take it.
fn naked_single(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  use index <- list.find_map(board.indices())
  case candidates(marks, index) {
    [digit] -> Ok(Step(NakedSingle, Settle(index, digit), [index], [digit], []))
    _ -> Error(Nil)
  }
}

/// A digit with one cell left in a unit has to go there, however much else
/// that cell could have taken.
fn hidden_single(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  use unit <- list.find_map(board.units())
  use digit <- list.find_map(board.span(1, board.side))
  case holding(marks, unit, digit) {
    [index] ->
      Ok(Step(HiddenSingle, Settle(index, digit), [index], [digit], unit))
    _ -> Error(Nil)
  }
}

/// Where a box and a line cross, a digit shut into the crossing from one
/// side is shut out of the rest of the other.
fn locked_candidates(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  case pointing(marks) {
    Ok(step) -> Ok(step)
    Error(_) -> claiming(marks)
  }
}

/// A digit that can only go in one row of a box cannot go anywhere else in
/// that row.
fn pointing(marks: Pencil) -> Result(Step, Nil) {
  use box <- list.find_map(board.boxes())
  use digit <- list.find_map(board.span(1, board.side))

  case holding(marks, box, digit) {
    [] | [_] -> Error(Nil)
    cells ->
      case shared_line(cells) {
        Error(_) -> Error(Nil)
        Ok(line) ->
          rule_out(
            marks,
            cells: except(line, box),
            digits: [digit],
            about: [digit],
            technique: LockedCandidates,
            evidence: cells,
            unit: line,
          )
      }
  }
}

/// A digit that can only go in one box's worth of a row cannot go anywhere
/// else in that box.
fn claiming(marks: Pencil) -> Result(Step, Nil) {
  use line <- list.find_map(list.append(board.rows(), board.columns()))
  use digit <- list.find_map(board.span(1, board.side))

  case holding(marks, line, digit) {
    [] | [_] -> Error(Nil)
    cells ->
      case shared_box(cells) {
        Error(_) -> Error(Nil)
        Ok(box) ->
          rule_out(
            marks,
            cells: except(box, line),
            digits: [digit],
            about: [digit],
            technique: LockedCandidates,
            evidence: cells,
            unit: box,
          )
      }
  }
}

/// Two cells in a unit holding the same two candidates have one each between
/// them, whichever way round, so nothing else in the unit can have either.
fn naked_pair(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  naked_subset(marks, 2, NakedPair)
}

/// The same again with three cells and three digits.
fn naked_triple(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  naked_subset(marks, 3, NakedTriple)
}

fn naked_subset(
  marks: Pencil,
  size: Int,
  technique: Technique,
) -> Result(Step, Nil) {
  use unit <- list.find_map(board.units())
  use group <- list.find_map(combinations(open(marks, unit), size))

  let digits = union(marks, group)
  case set.size(digits) == size {
    False -> Error(Nil)
    True ->
      rule_out(
        marks,
        cells: except(unit, group),
        digits: set.to_list(digits),
        about: set.to_list(digits),
        technique: technique,
        evidence: group,
        unit: unit,
      )
  }
}

/// Two digits in a unit with the same two cells to go in take one each,
/// whichever way round, so those cells can hold nothing else.
fn hidden_pair(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  use unit <- list.find_map(board.units())
  use pair <- list.find_map(combinations(board.span(1, board.side), 2))

  case pair {
    [one, other] -> {
      let cells = holding(marks, unit, one)
      case list.length(cells) == 2 && cells == holding(marks, unit, other) {
        False -> Error(Nil)
        True ->
          rule_out(
            marks,
            cells: cells,
            digits: except(set.to_list(union(marks, cells)), pair),
            about: pair,
            technique: HiddenPair,
            evidence: cells,
            unit: unit,
          )
      }
    }
    _ -> Error(Nil)
  }
}

/// Two rows where a digit is down to the same two columns make a rectangle.
/// The digit takes one corner in each row, so it takes one in each column
/// too, and is shut out of the rest of both columns.
fn x_wing(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  fishing(marks, 2, XWing)
}

/// The same argument over three lines. Three rows whose every candidate for
/// a digit falls in the same three columns take one apiece, so the three
/// columns are spoken for and every other cell in them loses it.
///
/// Harder to see than an X-wing for the same reason it is the same
/// argument: the rectangle a pair of rows makes is a shape, and three rows
/// make no shape at all. Each of the three may have two cells or three, and
/// they need not be the same two.
fn swordfish(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  fishing(marks, 3, Swordfish)
}

/// Look for one of these, both ways round: rows shutting a digit into
/// columns, and columns shutting it into rows.
fn fishing(
  marks: Pencil,
  size: Int,
  technique: Technique,
) -> Result(Step, Nil) {
  use digit <- list.find_map(board.span(1, board.side))

  case
    fish(
      marks,
      digit,
      size,
      technique,
      board.rows(),
      board.col_of,
      board.columns(),
    )
  {
    Ok(step) -> Ok(step)
    Error(_) ->
      fish(
        marks,
        digit,
        size,
        technique,
        board.columns(),
        board.row_of,
        board.rows(),
      )
  }
}

/// A digit shut into as many crossing lines as the lines it was read from.
///
/// `size` lines, each holding the digit in at least two cells and at most
/// `size` of them, whose cells fall between them in exactly `size` crossing
/// lines. Those crossings then hold one of the digit apiece and have none to
/// spare, so every other cell in them loses it.
///
/// Two of everything is an X-wing and three is a swordfish. A line with the
/// digit in only one cell is left out: that is a hidden single, which is
/// eight ranks easier and will have been taken long before this is reached.
fn fish(
  marks: Pencil,
  digit: Int,
  size: Int,
  technique: Technique,
  lines: List(List(Int)),
  crossing_of: fn(Int) -> Int,
  crossings: List(List(Int)),
) -> Result(Step, Nil) {
  let candidates = {
    use line <- list.filter_map(lines)
    let cells = holding(marks, line, digit)
    let count = list.length(cells)

    case count >= 2 && count <= size {
      True -> Ok(#(cells, list.map(cells, crossing_of) |> spread))
      False -> Error(Nil)
    }
  }

  use chosen <- list.find_map(combinations(candidates, size))

  let corners = list.flat_map(chosen, fn(line) { line.0 })
  let across = chosen |> list.flat_map(fn(line) { line.1 }) |> spread

  case list.length(across) == size {
    False -> Error(Nil)
    True -> {
      let targets =
        across
        |> list.flat_map(fn(at) { line_at(crossings, at) })
        |> except(corners)

      rule_out(
        marks,
        cells: targets,
        digits: [digit],
        about: [digit],
        technique: technique,
        evidence: corners,
        unit: [],
      )
    }
  }
}

/// Three cells of two candidates apiece: a pivot holding XY, and two wings
/// it can see holding XZ and YZ.
///
/// Whichever of its two the pivot turns out to be, one of the wings is left
/// holding Z — so nothing that can see both wings can be a Z, whether or not
/// it can see the pivot at all.
///
/// The first technique here that is not read off a single unit. Everything
/// above it argues inside a row, a column or a box, or across a rectangle of
/// them; this one follows a digit from cell to cell, and the three cells
/// need share no unit between them.
fn xy_wing(_grid: Grid, marks: Pencil) -> Result(Step, Nil) {
  let pairs = {
    use index <- list.filter(board.indices())
    list.length(candidates(marks, index)) == 2
  }

  use pivot <- list.find_map(pairs)

  let wings = {
    use index <- list.filter(pairs)
    index != pivot && list.contains(board.peers_of(pivot), index)
  }

  use both <- list.find_map(combinations(wings, 2))

  case candidates(marks, pivot), both {
    [x, y], [one, other] ->
      // The wings are alike, so which of them holds the pivot's first digit
      // is a thing to try rather than to know.
      case hinged(marks, pivot, x, y, one, other) {
        Ok(step) -> Ok(step)
        Error(_) -> hinged(marks, pivot, x, y, other, one)
      }
    _, _ -> Error(Nil)
  }
}

/// One wing holding X and Z, the other holding Y and Z, and what that leaves
/// for the cells which can see them both.
fn hinged(
  marks: Pencil,
  pivot: Int,
  x: Int,
  y: Int,
  one: Int,
  other: Int,
) -> Result(Step, Nil) {
  case except(candidates(marks, one), [x]) {
    [z] if z != y ->
      case candidates(marks, other) == spread([y, z]) {
        False -> Error(Nil)
        True ->
          rule_out(
            marks,
            cells: seen_by_both(one, other) |> except([pivot, one, other]),
            digits: [z],
            about: [z],
            technique: XYWing,
            evidence: [pivot, one, other],
            unit: [],
          )
      }
    _ -> Error(Nil)
  }
}

/// The cells that share a row, a column or a box with each of two cells.
fn seen_by_both(one: Int, other: Int) -> List(Int) {
  let theirs = board.peers_of(other)
  list.filter(board.peers_of(one), list.contains(theirs, _))
}

// ---------------------------------------------------------------------------
// Reading and writing candidates
// ---------------------------------------------------------------------------

/// A step that rules digits out, but only if there is anything there to rule
/// out. A technique that changes nothing has not been used.
fn rule_out(
  marks: Pencil,
  cells cells: List(Int),
  digits digits: List(Int),
  about about: List(Int),
  technique technique: Technique,
  evidence evidence: List(Int),
  unit unit: List(Int),
) -> Result(Step, Nil) {
  let touched = {
    use index <- list.filter(cells)
    list.any(digits, fn(digit) { has(marks, index, digit) })
  }

  case touched {
    [] -> Error(Nil)
    _ -> Ok(Step(technique, RuleOut(touched, digits), evidence, about, unit))
  }
}

fn has(marks: Pencil, index: Int, digit: Int) -> Bool {
  case dict.get(marks, index) {
    Ok(digits) -> set.contains(digits, digit)
    Error(_) -> False
  }
}

fn candidates(marks: Pencil, index: Int) -> List(Int) {
  case dict.get(marks, index) {
    Ok(digits) -> digits |> set.to_list |> list.sort(int.compare)
    Error(_) -> []
  }
}

/// The cells of a unit that could still take a digit.
fn holding(marks: Pencil, cells: List(Int), digit: Int) -> List(Int) {
  list.filter(cells, fn(index) { has(marks, index, digit) })
}

/// The cells of a unit that are still empty.
fn open(marks: Pencil, cells: List(Int)) -> List(Int) {
  list.filter(cells, dict.has_key(marks, _))
}

/// Everything the cells could hold between them.
fn union(marks: Pencil, cells: List(Int)) -> Set(Int) {
  use digits, index <- list.fold(cells, set.new())
  case dict.get(marks, index) {
    Ok(theirs) -> set.union(digits, theirs)
    Error(_) -> digits
  }
}

// ---------------------------------------------------------------------------
// Odds and ends
// ---------------------------------------------------------------------------

fn except(values: List(Int), leave_out: List(Int)) -> List(Int) {
  list.filter(values, fn(value) { !list.contains(leave_out, value) })
}

/// The row or column all of the cells lie in, if there is one.
fn shared_line(cells: List(Int)) -> Result(List(Int), Nil) {
  case all_alike(cells, board.row_of), all_alike(cells, board.col_of) {
    Ok(row), _ -> Ok(line_at(board.rows(), row))
    _, Ok(column) -> Ok(line_at(board.columns(), column))
    _, _ -> Error(Nil)
  }
}

/// The box all of the cells lie in, if there is one.
fn shared_box(cells: List(Int)) -> Result(List(Int), Nil) {
  case all_alike(cells, board.box_of) {
    Ok(box) -> Ok(line_at(board.boxes(), box))
    Error(_) -> Error(Nil)
  }
}

fn all_alike(cells: List(Int), of: fn(Int) -> Int) -> Result(Int, Nil) {
  case list.map(cells, of) {
    [] -> Error(Nil)
    [first, ..rest] ->
      case list.all(rest, fn(value) { value == first }) {
        True -> Ok(first)
        False -> Error(Nil)
      }
  }
}

fn line_at(lines: List(List(Int)), at: Int) -> List(Int) {
  case list.drop(lines, at) {
    [line, ..] -> line
    [] -> []
  }
}

/// Every way of choosing `size` of the values, order not counting.
fn combinations(values: List(a), size: Int) -> List(List(a)) {
  case size, values {
    0, _ -> [[]]
    _, [] -> []
    _, [first, ..rest] ->
      list.append(
        list.map(combinations(rest, size - 1), fn(group) { [first, ..group] }),
        combinations(rest, size),
      )
  }
}
