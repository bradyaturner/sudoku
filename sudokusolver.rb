#!/usr/bin/env ruby

require 'logger'

require './sudokupuzzle.rb'
require './loggerconfig'
require './exceptions'

MAX_ITERATIONS = 1000

RULES = [
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
    update_possible_values
    RULES.each do |rule|
      send rule
      # TODO run this every time a candidate value changes, not just after every rule application
      update_possible_values
      singles
    end
    state_before_update != @puzzle.serialize_with_candidates
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
    @puzzle.cells.each_with_index do |v,index|
      next if v.solved?
      @logger.info "Guessing values for (#{v.row},#{v.col}): #{v.possible_values}"
      pos_values = v.possible_values
      pos_values.each do |pv|
        begin
          @logger.info "Guessing value for (#{v.row},#{v.col}): #{v.possible_values}: (#{pv})"
          v.set_value pv
          data = @puzzle.serialize_with_candidates
          new_solver = SudokuSolver.new(SudokuPuzzle.new(data, true), @brute_force)
          success = new_solver.solve
          return true if success
        rescue ImpossibleValueError => e # encountering an impossible value when guessing just means it was a bad guess
          @logger.info "Guessing value FAILED: (#{v.row},#{v.col}): #{v.possible_values}: (#{pv})"
          v.set_possible_values pos_values
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
      groups = get_groups cell, false

      groups.each do |group|
        value = cell.possible_values.detect do |v|
          !group.collect{|c| c.possible_values}.flatten.include? v
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
    groups = get_groups cell, false
    groups.each do |group|
      group.each do |c|
        c.remove_possible_value value
      end
    end
  end

  # for each unsolved cell, remove candidate values for all solved cells in its groups
  def update_possible_values
    @logger.info "Applying rule: Update Possible Values"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      @logger.debug cell.to_s

      groups_content = get_groups(cell, false).flatten.collect{|gi| gi.value}
      excluded = (groups_content - [0]).uniq

      if (cell.possible_values & excluded).length > 0
        cell.remove_possible_values(excluded)
      end
      @logger.debug "\tPossible: #{cell.possible_values}#{cell.solved? ? " (solved)" : ""}"
    end
  end

  # for each unsolved cell, check if any of its candidates in a grid are restricted to a row or column
  # if so, they can be excluded from the other cells in the row or column outside the box
  def locked_candidates_1
    @logger.info "Applying rule: Locked Candidates 1"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      row, col, grid = get_groups cell, true
      cell.possible_values.each do |pv|
        grid_candidates = grid.select{|c| c.possible_values.include? pv}
        [row, col].each do |group|
          group_in_grid = group.select {|c| grid.include? c}
          group_out_grid = group - group_in_grid

          group_candidates = group_in_grid.select{|c| c.possible_values.include? pv}
          if grid_candidates.length == group_candidates.length
            group_out_grid.each do |c|
              c.remove_possible_value pv
            end
          end
        end
      end
    end
  end

  # for each unsolved cell, see if its candidate values exist only in its grid, for its row or column
  # if so, then that candidate can be removed from all other cells in the grid outside the row or column
  def locked_candidates_2
    @logger.info "Applying rule: Locked Candidates 2"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      row, col, grid = get_groups cell

      cell.possible_values.each do |v|
        ri = row.select{|rc| grid.include?(rc)}.select{|rc| rc.possible_values.include? v}.length
        ci = col.select{|cc| grid.include?(cc)}.select{|cc| cc.possible_values.include? v}.length
        gi = grid.select{|gc| gc.possible_values.include? v}.length

        if (gi == ri)
          grid.each do |cell2|
            if !row.include?(cell2) && !cell2.solved?
              cell2.remove_possible_values [v]
            end
          end
        elsif (gi == ci)
          grid.each do |cell2|
            if !col.include?(cell2) && !cell2.solved?
              cell2.remove_possible_values [v]
            end
          end
        end
      end
    end
  end

  def naked_pairs
    @logger.info "Applying rule: Naked Pairs"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      next if cell.possible_values.length != 2
      get_groups(cell, false).each {|g| check_group_naked_pairs(cell, g)}
    end
  end

  def check_group_naked_pairs(cell, group)
    gi = group.select{|gc| gc.possible_values == cell.possible_values}
    if gi.length == 2
      @logger.info "Found naked pair at (#{gi.first.row},#{gi.first.col}) and (#{gi.last.row},#{gi.last.col}) for values #{cell.possible_values.inspect}"
      group.select{|c|!gi.include?(c) && !c.solved?}.each do |cell2|
        cell2.remove_possible_values cell.possible_values
      end
    end
  end

  # TODO cannot do this as a batch -- removing candidates after pairs have been calculated DOES NOT WORK!
  # refactor this to be a single iteration that works on any group type
  def hidden_pairs
    @logger.info "Applying rule: Hidden Pairs"
    @puzzle.cells.each do |cell|
      next if cell.solved?
      next if cell.possible_values.length < 2
      get_groups(cell, false).each {|g| check_group_hidden_pairs(cell, g)}
    end
  end

  def check_group_hidden_pairs(cell, group)
    gi = group.select do |pc|
      pvs = pc.possible_values & cell.possible_values
      other_cells = group.select{|c| c!=pc}.select{|c| (c.possible_values & pvs) == pvs}
      next if !(pvs.length == 2 && other_cells.length == 0)
      @logger.info "Found hidden pair at (#{cell.row},#{cell.col}) and (#{pc.row},#{pc.col}) for values #{pvs.inspect}"
      [cell, pc].each {|c2| c2.remove_possible_values(SORTED_NUMBERS-pvs) }
    end
  end

  def get_groups(cell, include_self=true)
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
    print_possible_values
  end

  def print_possible_values
    @puzzle.cells.each_with_index do |value,index|
      next if value.solved?
      puts "\t(#{value.row},#{value.col}): #{value.possible_values}"
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
