#!/usr/bin/env ruby

require 'logger'

require './sudokupuzzle.rb'
require './loggerconfig'
require './exceptions'

MAX_ITERATIONS = 1000

RULES = [
  :singles,
  :hidden_singles,
  :locked_candidates_1,
  :locked_candidates_2,
  :naked_pairs,
#  :hidden_pairs
]

class SudokuSolver
  def initialize(puzzle, brute_force=false)
    @puzzle = puzzle
    @brute_force = brute_force
    @iterations = 0
    @logger = Logger.new(STDERR)
    @logger.level = LoggerConfig::SUDOKUSOLVER_LEVEL
  end

  def apply_rules
    state_before_update = @puzzle.serialize_with_candidates
    apply_rule :update_candidates
    RULES.each do |rule|
      apply_rule rule
      # TODO run this every time a candidate value changes, not just after every rule application -- maybe?
      apply_rule :singles
    end
    state_before_update != @puzzle.serialize_with_candidates
  end

  def apply_rule(rule)
    before = @puzzle.serialize_with_candidates
    send rule
    changed = (before == @puzzle.serialize_with_candidates)
    @logger.info "Application of rule #{rule} did #{changed ? "":"not "}advance state."
    changed
  end

  def solve
    puts "Solving puzzle..."
    puts "Brute force guessing is *#{@brute_force ? "ON" : "OFF"}*"
    @puzzle.print_puzzle(true)
    begin
      loop do
        break if @puzzle.solved? # need to check first for already-solved puzzles
        @puzzle.print_puzzle
        @logger.info "*** beginning update iteration #{@iterations} ***"
        was_updated = apply_rules
        @logger.info "*** update iteration #{@iterations} complete ***"
        if !was_updated && @brute_force
          return brute_force_solve
        elsif !was_updated
          raise UnsolvableError, "Update iteration ran with no changes made -- puzzle in unsolvable state!!"
        end
        break if @puzzle.solved?
        @iterations += 1
        if @iterations >= MAX_ITERATIONS
          raise UnsolvableError, "Could not solve puzzle in #{MAX_ITERATIONS} iterations. LITERALLY UNSOLVABLE!!"
        end
      end
      print_success
    rescue SudokuError => e
      puts e.message
      print_failure
    end
    @puzzle.solved?
  end

  def brute_force_solve
    @puzzle.cells.each do |v|
      next if v.solved?
      @logger.info "Guessing values for (#{v.row},#{v.col}): #{v.candidates}"
      pos_values = v.candidates
      pos_values.each do |pv|
        begin
          @logger.info "Guessing value for (#{v.row},#{v.col}): #{v.candidates}: (#{pv})"
          v.set_value pv
          data = @puzzle.serialize_with_candidates
          new_solver = SudokuSolver.new(SudokuPuzzle.new(data, true), @brute_force)
          success = new_solver.solve
          return true if success
        rescue ImpossibleValueError => e # encountering an imcandidate value when guessing just means it was a bad guess
          @logger.info "Guessing value FAILED: (#{v.row},#{v.col}): #{v.candidates}: (#{pv})"
          v.set_candidates pos_values
        end
      end
    end
    raise UnsolvableError, "Could not find a solution even with guessing."
  end

  # for each unsolved cell, check to see if it is the only cell in any of its groups
  # that can contain a specific value
  def hidden_singles
    @logger.info "Applying rule: Hidden Singles"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      @logger.debug cell.to_s
      groups = get_groups cell

      groups.each do |group|
        value = cell.candidates.detect do |v|
          !group.collect{|c| c.candidates}.flatten.include? v
        end
        if value
          cell.set_value(value)
          remove_candidate_from_cell_groups(cell, value)
          break
        end
      end
    end
  end

  # for each unsolved cell, assign values to any who have only one candidate value
  def singles
    @logger.info "Applying rule: Singles"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      @logger.debug cell.to_s
      if v = cell.update_value
        remove_candidate_from_cell_groups(cell, v)
      end
    end
  end

  def remove_candidate_from_cell_groups(cell, value)
    @logger.debug "Removing value #{value} from all groups for cell (#{cell.row},#{cell.col})."
    groups = get_groups cell
    groups.flatten.each do |c|
      c.remove_candidate value
    end
  end

  # for each unsolved cell, remove candidate values for all solved cells in its groups
  def update_candidates
    @logger.info "Applying rule: Update Candidate Values"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      @logger.debug cell.to_s

      groups_content = get_groups(cell).flatten.collect{|gi| gi.value}
      excluded = (groups_content - [0]).uniq

      if (cell.candidates & excluded).length > 0
        cell.remove_candidates(excluded)
      end
    end
  end

  # for each unsolved cell, check if any of its candidates in a grid are restricted to a row or column
  # if so, they can be excluded from the other cells in the row or column outside the box
  def locked_candidates_1
    @logger.info "Applying rule: Locked Candidates 1"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      row, col, grid = get_groups(cell, true)
      cell.candidates.each do |pv|
        [row, col].each {|g| locked_candidates(g, grid, pv) }
      end
    end
  end

  # find candidate values in rows or columns that are restricted to a grid
  # remove that candidate from other cells in the grid
  def locked_candidates_2
    @logger.info "Applying rule: Locked Candidates 2"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      row, col, grid = get_groups(cell, true)
      cell.candidates.each do |cv|
        [row, col].each {|g| locked_candidates(grid, g, cv) }
      end
    end
  end

  def locked_candidates(group, filter, value)
    num_in_filter = cells_with_candidate(filter, value)
    num_in_filtered_group = cells_with_candidate((group&filter), value)
    if num_in_filter == num_in_filtered_group
      (group-filter).each {|c| c.remove_candidate value}
    end
  end

  def cells_with_candidate(group, value)
    group.select{|c| c.candidates.include? value}
  end

  def naked_pairs
    @logger.info "Applying rule: Naked Pairs"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      next if cell.candidates.length != 2
      get_groups(cell).each {|g| check_group_naked_pairs(cell, g)}
    end
  end

  def check_group_naked_pairs(cell, group)
    gi = group.select{|gc| gc.candidates == cell.candidates}
    if gi.length == 2
      @logger.info "Found naked pair at (#{gi.first.row},#{gi.first.col}) and (#{gi.last.row},#{gi.last.col}) for values #{cell.candidates.inspect}"
      group.select{|c|!gi.include?(c) && !c.solved?}.each do |cell2|
        cell2.remove_candidates cell.candidates
      end
    end
  end

  # TODO cannot do this as a batch -- removing candidates after pairs have been calculated DOES NOT WORK!
  # refactor this to be a single iteration that works on any group type
  def hidden_pairs
    @logger.info "Applying rule: Hidden Pairs"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      next if cell.candidates.length < 2
      get_groups(cell).each {|g| check_group_hidden_pairs(cell, g)}
    end
  end

  def check_group_hidden_pairs(cell, group)
    gi = group.select do |pc|
      pvs = pc.candidates & cell.candidates
      other_cells = group.select{|c| c!=pc}.select{|c| (c.candidates & pvs) == pvs}
      next if !(pvs.length == 2 && other_cells.length == 0)
      @logger.info "Found hidden pair at (#{cell.row},#{cell.col}) and (#{pc.row},#{pc.col}) for values #{pvs.inspect}"
      [cell, pc].each {|c2| c2.remove_candidates(SORTED_NUMBERS-pvs) }
    end
  end

  def get_groups(cell, include_self=false)
    row = @puzzle.get_row(cell.row).select{|c| !include_self ? c!=cell : true }
    col = @puzzle.get_column(cell.col).select{|c| !include_self ? c!=cell : true}
    grid = @puzzle.get_grid(cell.grid).select{|c| !include_self ? c!=cell : true}
    [row, col, grid]
  end

# output methods
  def print_success(puzzle=@puzzle)
    puts "SOLVED!"
    puts "Initial state:"
    @puzzle.print_puzzle(true)
    puts "Solution:"
    puzzle.print_puzzle
    puts puzzle.serialize
    puts "Solved in #{@iterations} iterations."
  end

  def print_failure
    puts "FAILED."
    puts "Initial state:"
    @puzzle.print_puzzle(true)
    puts "Final state:"
    @puzzle.print_puzzle
    puts "Gave up after #{@iterations} iterations."
    puts "Numbers remaining: #{@puzzle.remaining_numbers}"
    print_candidates
  end

  def print_candidates
    @puzzle.cells.each do |value|
      next if value.solved?
      puts "\t(#{value.row},#{value.col}): #{value.candidates}"
    end
  end
end

if __FILE__==$0
  if !ARGV[0]
    STDERR.puts "USAGE: #{__FILE__} [FILE] <brute_force>"
    exit 0
  end
  brute_force = ARGV[1]

  time_start = Time.now
  puzzles = SudokuReader.new(ARGV[0]).puzzles
  num_solved = 0
  not_solved = []
  puzzles.each_with_index do |p,i|
    solved = SudokuSolver.new(p, brute_force).solve
    if solved
      num_solved += 1
    else
      not_solved << i
    end
    puts "\n\n\n"
  end
  time_finish = Time.now

  puts "RESULTS:"
  puts "\tSolved #{num_solved} of #{puzzles.length} puzzles."
  puts "\tTotal time was #{time_finish-time_start} seconds."
  puts "\tCould not solve the following puzzles: #{not_solved.inspect}"
end
