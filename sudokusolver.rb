#!/usr/bin/env ruby

require 'logger'

require './sudokupuzzle.rb'
require './loggerconfig'
require './exceptions'

MAX_ITERATIONS = 1000
class SudokuSolver
  def initialize(puzzle, brute_force=false)
    @puzzle = puzzle
    @brute_force = brute_force
    @iterations = 0
    @logger = Logger.new(STDERR)
    @logger.level = LoggerConfig::SUDOKUSOLVER_LEVEL
  end

  def apply_rules
    before_update = @puzzle.serialize_with_candidates
    update_possible_values
    check_hidden_singles
    update_locked_candidates_1
    update_locked_candidates_2
    update_naked_pairs
    before_update != @puzzle.serialize_with_candidates
  end

  def solve
    puts "Solving puzzle..."
    puts "Brute force guessing is *#{@brute_force ? "ON" : "OFF"}*"
    @puzzle.print_puzzle(true)
    begin
      loop do
        break if @puzzle.solved? # need to check first for already-solved puzzles
        @logger.debug "*** beginning update iteration #{@iterations} ***"
        was_updated = apply_rules
        @logger.debug "*** update iteration #{@iterations} complete ***"
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
    @puzzle.data.each_with_index do |v,index|
      next if v.solved?
      row_num = index / 9
      col_num = index % 9
      puts "Guessing value for (#{row_num},#{col_num}): #{v.possible_values}"
      v.possible_values.each do |pv|
        begin
          data = @puzzle.serialize
          data[index] = "#{pv}"
          new_solver = SudokuSolver.new(SudokuPuzzle.new(data), @brute_force)
          success = new_solver.solve
          return true if success
          rescue ImpossibleValueError # encountering an impossible value when guessing just means it was a bad guess
        end
      end
    end
    raise UnsolvableError, "Could not find a solution even with guessing."
  end

  # for each unsolved cell, look at its groups to see if it is the
  # only resident containing a specific candidate value
  def check_hidden_singles
    @puzzle.data.each do |cell|
      next if cell.solved?
      @logger.debug cell.to_s
      row, col, grid = get_groups cell

      new_value = nil
      cell.possible_values.each do |v|
        @logger.debug "\tChecking possible value: #{v}"
        ri = row.select{|rc| rc.possible_values.include? v}.length
        @logger.debug "\t#{ri} elegible items in this row."
        ci = col.select{|cc| cc.possible_values.include? v}.length
        @logger.debug "\t#{ci} elegible items in this column."
        gi = grid.select{|gc| gc.possible_values.include? v}.length
        @logger.debug "\t#{gi} elegible items in this grid."
        if (ri == 1) || (ci == 1) || (gi == 1)
          new_value = v
          break
        end
      end
      if !new_value.nil?
        cell.set_value(new_value)
      end
    end
  end

  # for each unsolved cell, remove candidate values for all solved cells in its groups
  def update_possible_values
    @puzzle.data.each do |value|
      next if value.solved?
      @logger.debug value.to_s

      row_contents = @puzzle.get_row_values value.row_num
      col_contents = @puzzle.get_column_values value.col_num
      grid_contents = @puzzle.get_grid_values value.grid_num
      excluded = (row_contents + col_contents + grid_contents - [0]).uniq

      if (value.possible_values & excluded).length > 0
        value.remove_possible_values(excluded)
      end
      @logger.debug "\tPossible: #{value.possible_values}#{value.solved? ? " (solved)" : ""}"
    end
  end

  # for each unsolved cell, see if its candidate values exist only in its row or column, for its grid
  # if so, then that candidate can be removed from all other cells in the row or column outside the grid
  def update_locked_candidates_1
    @logger.debug "Applying rule: Locked Candidates 1"
    @puzzle.data.each do |cell|
      next if cell.solved?
      row, col, grid = get_groups cell

      cell.possible_values.each do |v|
        ri = row.select{|rc| grid.include?(rc)}.select{|rc| rc.possible_values.include? v}.length
        ci = col.select{|cc| grid.include?(cc)}.select{|cc| cc.possible_values.include? v}.length
        gi = grid.select{|gc| gc.possible_values.include? v}.length

        if (gi == ri)
          row.each do |cell2|
            if !grid.include?(cell2) && !cell2.solved?
              cell2.remove_possible_values [v]
            end
          end
        elsif (gi == ci)
          col.each do |cell2|
            if !grid.include?(cell2) && !cell2.solved?
              cell2.remove_possible_values [v]
            end
          end
        end
      end
    end
  end

  # for each unsolved cell, see if its candidate values exist only in its grid, for its row or column
  # if so, then that candidate can be removed from all other cells in the grid outside the row or column
  def update_locked_candidates_2
    @logger.debug "Applying rule: Locked Candidates 2"
    @puzzle.data.each do |cell|
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

  def update_naked_pairs
    @logger.info "Applying rule: Naked Pairs"
    @puzzle.data.each do |cell|
      next if cell.solved?
      next if cell.possible_values.length != 2
      row, col, grid = get_groups cell
      ri = row.select{|rc| rc.possible_values == cell.possible_values}
      ci = col.select{|cc| cc.possible_values == cell.possible_values}
      gi = grid.select{|gc| gc.possible_values == cell.possible_values}

      group = nil
      pairs = nil
      if ri.length == 2 # row pairs
#        print_possible_values
        @logger.info "Found row naked pair at (#{ri.first.row_num},#{ri.first.col_num}) and (#{ri.last.row_num},#{ri.last.col_num}) for values #{cell.possible_values.inspect}"
        group = row
        pairs = ri
      elsif ci.length == 2 # col pairs
#        print_possible_values
        @logger.info "Found col naked pair at (#{ri.first.row_num},#{ri.first.col_num}) and (#{ri.last.row_num},#{ri.last.col_num}) for values #{cell.possible_values.inspect}"
        group = col
        pairs = ci
      elsif gi.length == 2 # grid pairs
#        print_possible_values
        @logger.info "Found grid naked pair at (#{ri.first.row_num},#{ri.first.col_num}) and (#{ri.last.row_num},#{ri.last.col_num}) for values #{cell.possible_values.inspect}"
        group = grid
        pairs = gi
      end
      if group
        group.select{|c|!pairs.include?(c) && !c.solved?}.each do |cell2|
          cell2.remove_possible_values cell.possible_values
        end
#        print_possible_values
      end
    end
  end

  def get_groups(cell)
    row = @puzzle.get_row cell.row_num
    col = @puzzle.get_column cell.col_num
    grid = @puzzle.get_grid cell.grid_num
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
    @puzzle.data.each_with_index do |value,index|
      next if value.solved?
      row_num = index / 9
      col_num = index % 9
      puts "\t(#{row_num},#{col_num}): #{value.possible_values}"
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
