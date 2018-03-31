#!/usr/bin/env ruby

require 'logger'

require './sudokupuzzle.rb'
require './loggerconfig'
require './exceptions'

MAX_ITERATIONS = 1000
class SudokuSolver
  def initialize(puzzle)
    @puzzle = puzzle
    @iterations = 0
    @logger = Logger.new(STDERR)
    @logger.level = LoggerConfig::SUDOKUSOLVER_LEVEL
  end

  def solve
    puts "Solving puzzle..."
    @puzzle.print_puzzle(true)
    begin
      loop do
        break if @puzzle.solved? # need to check first for already-solved puzzles
        @logger.debug "*** beginning update iteration #{@iterations} ***"
        update_count = update_possible_values
        update_count += check_value_candidates
        @logger.debug "*** update iteration #{@iterations} complete ***"
        if update_count == 0
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

  def print_success
    puts "SOLVED!"
    puts "Initial state:"
    @puzzle.print_puzzle(true)
    puts "Solution:"
    @puzzle.print_puzzle
    puts @puzzle.serialize
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

  def update_possible_values
    update_count = 0
    @puzzle.data.each_with_index do |value,index|
      next if value.solved?
      @logger.debug value.to_s

      row_contents = @puzzle.get_row_values value.row_num
      col_contents = @puzzle.get_column_values value.col_num
      grid_contents = @puzzle.get_grid_values value.grid_num
      excluded = (row_contents + col_contents + grid_contents - [0]).uniq

      if (value.possible_values & excluded).length > 0
        update_count += 1
        value.remove_possible_values(excluded)
      end
      @logger.debug "\tPossible: #{value.possible_values}#{value.solved? ? " (solved)" : ""}"
    end
    update_count
  end

  def check_value_candidates
    update_count = 0
    @puzzle.data.each_with_index do |value,index|
      next if value.solved?
      @logger.debug value.to_s

      row_contents = @puzzle.get_row value.row_num
      col_contents = @puzzle.get_column value.col_num
      grid_contents = @puzzle.get_grid value.grid_num

      new_value = nil
      value.possible_values.each do |v|
        @logger.debug "\tChecking possible value: #{v}"
        ri = row_contents.select{|rc| rc.possible_values.include? v}.length
        @logger.debug "\t#{ri} elegible items in this row."
        ci = col_contents.select{|cc| cc.possible_values.include? v}.length
        @logger.debug "\t#{ci} elegible items in this column."
        gi = grid_contents.select{|gc| gc.possible_values.include? v}.length
        @logger.debug "\t#{gi} elegible items in this grid."
        if (ri == 1) || (ci == 1) || (gi == 1)
          new_value = v
          break
        end
      end
      if !new_value.nil?
        value.set_value(new_value)
        update_count += 1
      end
    end
    update_count
  end
end

if __FILE__==$0
  if !ARGV[0]
    STDERR.puts "USAGE: #{__FILE__} [FILE]"
    exit 0
  end

  time_start = Time.now
  puzzles = SudokuReader.new(ARGV[0]).puzzles
  num_solved = 0
  not_solved = []
  puzzles.each_with_index do |p,i|
    solved = SudokuSolver.new(p).solve
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
