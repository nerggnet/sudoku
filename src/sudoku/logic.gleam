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
  }
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
  step(grid, pencil(grid))
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

    XWing, RuleOut(cells, _) -> {
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
    few if few <= 3 -> named(cells)
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
      named(step.evidence)
      <> " take "
      <> written(step.about)
      <> " between them."

    HiddenPair, RuleOut(_, _) ->
      "only "
      <> named(step.evidence)
      <> " can take "
      <> either(step.about)
      <> " in their "
      <> unit_kind(step.unit)
      <> "."

    XWing, RuleOut(_, _) -> {
      let #(base, cover) = case reads_across(step) {
        True -> #(rows_of(step.evidence), columns_of(step.evidence))
        False -> #(columns_of(step.evidence), rows_of(step.evidence))
      }

      "a "
      <> written(step.about)
      <> " in "
      <> base
      <> " keeps to "
      <> cover
      <> "."
    }

    // Every technique has its own words above; this is only reached if one
    // is added without them.
    _, Settle(index, digit) ->
      board.name(index) <> " is a " <> int.to_string(digit) <> "."
    _, RuleOut(cells, digits) ->
      "no " <> written(digits) <> " in " <> named(cells) <> "."
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
    _, _, _ -> named(cells)
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

fn named(cells: List(Int)) -> String {
  cells |> list.map(board.name) |> joined("and")
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
  use digit <- list.find_map(board.span(1, board.side))

  case fish(marks, digit, board.rows(), board.col_of, board.columns()) {
    Ok(step) -> Ok(step)
    Error(_) -> fish(marks, digit, board.columns(), board.row_of, board.rows())
  }
}

fn fish(
  marks: Pencil,
  digit: Int,
  lines: List(List(Int)),
  crossing_of: fn(Int) -> Int,
  crossings: List(List(Int)),
) -> Result(Step, Nil) {
  // The lines where the digit has exactly two cells left, and which crossing
  // lines those are.
  let pairs = {
    use line <- list.filter_map(lines)
    case holding(marks, line, digit) {
      [one, other] ->
        Ok(#([one, other], [crossing_of(one), crossing_of(other)]))
      _ -> Error(Nil)
    }
  }

  use both <- list.find_map(combinations(pairs, 2))
  case both {
    [#(here, across), #(there, also)] ->
      case across == also {
        False -> Error(Nil)
        True -> {
          let corners = list.append(here, there)
          let targets =
            across
            |> list.flat_map(fn(at) { line_at(crossings, at) })
            |> except(corners)

          rule_out(
            marks,
            cells: targets,
            digits: [digit],
            about: [digit],
            technique: XWing,
            evidence: corners,
            unit: [],
          )
        }
      }
    _ -> Error(Nil)
  }
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
