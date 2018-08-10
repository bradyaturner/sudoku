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
    update_hidden_pairs
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

      row_contents = @puzzle.get_row_values value.row
      col_contents = @puzzle.get_column_values value.col
      grid_contents = @puzzle.get_grid_values value.grid
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

      if ri.length == 2 # row pairs
        @logger.info "Found row naked pair at (#{ri.first.row},#{ri.first.col}) and (#{ri.last.row},#{ri.last.col}) for values #{cell.possible_values.inspect}"
        row.select{|c|!ri.include?(c) && !c.solved?}.each do |cell2|
          cell2.remove_possible_values cell.possible_values
        end
      end

      if ci.length == 2 # col pairs
        @logger.info "Found col naked pair at (#{ci.first.row},#{ci.first.col}) and (#{ci.last.row},#{ci.last.col}) for values #{cell.possible_values.inspect}"
        col.select{|c|!ci.include?(c) && !c.solved?}.each do |cell2|
          cell2.remove_possible_values cell.possible_values
        end
      end

      if gi.length == 2 # grid pairs
        @logger.info "Found grid naked pair at (#{gi.first.row},#{gi.first.col}) and (#{gi.last.row},#{gi.last.col}) for values #{cell.possible_values.inspect}"
        grid.select{|c|!gi.include?(c) && !c.solved?}.each do |cell2|
          cell2.remove_possible_values cell.possible_values
        end
      end
    end
  end

  # TODO cannot do this as a batch -- removing candidates after pairs have been calculated DOES NOT WORK!
  # refactor this to be a single iteration that works on any group type

  def update_hidden_pairs
    @logger.info "Applying rule: Hidden Pairs"
    @puzzle.data.each do |cell|
      next if cell.solved?
      next if cell.possible_values.length < 2
      row, col, grid = get_groups(cell, false)
      ri = row.select do |pc|
        overlap = pc.possible_values & cell.possible_values
        puts "OVERLAP: (#{cell.row},#{cell.col}) , (#{pc.row},#{pc.col}) #{overlap.inspect}"
        other_cells = row.select{|c| c!=pc}.select{|c| (c.possible_values & overlap) == overlap}
        overlap.length == 2 && other_cells.length == 0
      end
      ci = col.select do |pc|
        overlap = pc.possible_values & cell.possible_values
        other_cells = col.select{|c| c!=pc}.select{|c| (c.possible_values & overlap) == overlap}
        overlap.length == 2 && other_cells.length == 0
      end
      gi = grid.select do |pc|
        overlap = pc.possible_values & cell.possible_values
        other_cells = grid.select{|c| c!=pc}.select{|c| (c.possible_values & overlap) == overlap}
        overlap.length == 2 && other_cells.length == 0
      end

      ri.each do |rp| # row pairs
        @puzzle.print_puzzle
        print_possible_values
        pvs = rp.possible_values & cell.possible_values
        @logger.info "Found row hidden pair at (#{cell.row},#{cell.col}) and (#{rp.row},#{rp.col}) for values #{pvs.inspect}"
        [cell, rp].each {|c2| c2.remove_possible_values(SORTED_NUMBERS-pvs) } # "remove all except" not the same operation as "set possible values"
      end

      ci.each do |cp| # col pairs
        @puzzle.print_puzzle
        print_possible_values
        pvs = cell.possible_values & cp.possible_values
        @logger.info "Found col hidden pair at (#{cell.row},#{cell.col}) and (#{cp.row},#{cp.col}) for values #{pvs.inspect}"
        [cell, cp].each {|c2| c2.remove_possible_values(SORTED_NUMBERS-pvs) }
      end

      gi.each do |gp| # grid pairs
        @puzzle.print_puzzle
        print_possible_values
        pvs = cell.possible_values & gp.possible_values
        @logger.info "Found grid hidden pair at (#{cell.row},#{cell.col}) and (#{gp.row},#{gp.col}) for values #{pvs.inspect}"
        gi.each {|c2| c2.remove_possible_values(SORTED_NUMBERS-pvs) }
      end
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
    @puzzle.data.each_with_index do |value,index|
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
