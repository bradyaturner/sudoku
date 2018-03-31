#!/usr/bin/env ruby

require 'logger'
require './loggerconfig'
require './exceptions'

PUZZLE_WIDTH = 9
PUZZLE_DISPLAY_WIDTH = 25
SORTED_NUMBERS = [1,2,3,4,5,6,7,8,9]
EMPTY_CHAR = "-"
MAX_ITERATIONS = 1000

class SudokuValue
  attr_reader :value, :initial_value, :possible_values
  def initialize(initial_value)
    @initial_value = initial_value
    @value = initial_value
    if @initial_value == 0
      @possible_values = Array.new(SORTED_NUMBERS) # TODO what to initialize this to?
    else
      @possible_values = [initial_value]
    end
  end

  def solved?
    (@value != 0) && (@possible_values.length == 1)
  end

  def set_value(v)
    raise ImpossibleValueError, "Not possible value! #{v}, #{@possible_values.inspect}" if !@possible_values.include?(v)
    @value = v
    @possible_values = [v]
  end

  def remove_possible_values(values)
    @possible_values -= values
    if @possible_values.length == 1
      @value = @possible_values.first
    elsif @possible_values.length <= 0
      raise ImpossibleValueError, "No possible values!"
    end
  end

  def to_s
    @value == 0 ? EMPTY_CHAR : @value
  end
end

class SudokuPuzzle
  attr_reader :data
  def initialize(data)
    @data = []
    data.delete("\r\n").split("").map(&:to_i).each do |v|
      @data << SudokuValue.new(v)
    end
  end

  def print_puzzle(initial_state=false)
    @data.each_with_index do |value,index|
      print_horizontal_line if (index%27 == 0)
      print "| " if (index%3 == 0)
      print initial_state ? (value.initial_value == 0 ? EMPTY_CHAR : value.initial_value) : value.to_s
      print (index+1)%9==0 ? " |\n" : " "
    end
    print_horizontal_line
  end

  def solved?
    solved = true
    (0..8).each do |i|
      solved = solved && validate_row(i) \
        && validate_column(i) \
        && validate_grid(i)
    end
    solved
  end

  def remaining_numbers
    numbers = Array.new(SORTED_NUMBERS)
    (0..8).each {|i| numbers &= get_grid_values(i)}
    SORTED_NUMBERS - numbers
  end

  def validate_row(num)
    get_row_values(num).sort == SORTED_NUMBERS
  end

  def validate_column(num)
    get_column_values(num).sort == SORTED_NUMBERS
  end

  def validate_grid(num)
    get_grid_values(num).sort == SORTED_NUMBERS
  end

  def get_row_values(num)
    get_row(num).collect{|v| v.value}
  end

  def get_row(num)
    @data[(num*PUZZLE_WIDTH)..(num*PUZZLE_WIDTH)+8]
  end

  def get_column_values(num)
    get_column(num).collect{|v| v.value}
  end

  def get_column(num)
    col = []
    @data.each_with_index {|val,index| col << val if (index%PUZZLE_WIDTH == num)}
    col 
  end

  def get_grid_values(num)
    get_grid(num).collect{|v| v.value}
  end

  def get_grid(num)
    start_row = (num/3) * 3
    start_col = (num%3) * 3
    grid = []
    (0..8).each {|i| grid << value_at(start_row+i/3,start_col+i%3)}
    grid
  end

  def print_horizontal_line
    puts "-" * PUZZLE_DISPLAY_WIDTH
  end

  def value_at(row,col)
    row_value(row,col)
  end

  def row_value(row,pos)
    @data[(row * PUZZLE_WIDTH) + pos]
  end

  def column_value(column,pos)
    @data[(pos * PUZZLE_WIDTH) + column]
  end

  def serialize
    @data.collect{|v| v.value}.join
  end
end

class SudokuReader
  attr_reader :puzzles
  def initialize(file)
    @file = File.read(file)
    @puzzles = []
    @file.each_line {|line| @puzzles << SudokuPuzzle.new(line)}
  end
end

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
  end

  def update_possible_values
    update_count = 0
    @puzzle.data.each_with_index do |value,index|
      next if value.solved?
      row_num = index / 9
      col_num = index % 9
      grid_num = ((row_num/3)*3) + (col_num/3)
      @logger.debug "Value #{value} at pos (#{row_num},#{col_num}) in grid ##{grid_num}"

      row_contents = @puzzle.get_row_values row_num
      col_contents = @puzzle.get_column_values col_num
      grid_contents = @puzzle.get_grid_values grid_num
      excluded = (row_contents + col_contents + grid_contents - [0]).uniq

      # only perform update and increment counter if there are actually items that would be removed
      if (value.possible_values & excluded).length > 0
        update_count += 1
        value.remove_possible_values(excluded)
      end
      @logger.debug "\tPossible: #{value.possible_values}#{value.solved? ? " (solved)" : ""}"
    end
    update_count
  end

  def check_value_candidates
    # TODO check row, col, grid for each ? value -- am I the only one who can be this value?
    update_count = 0
    @puzzle.data.each_with_index do |value,index|
      next if value.solved?
      row_num = index / 9
      col_num = index % 9
      grid_num = ((row_num/3)*3) + (col_num/3)
      @logger.debug "Value #{value} at pos (#{row_num},#{col_num}) in grid ##{grid_num}"

      row_contents = @puzzle.get_row row_num
      col_contents = @puzzle.get_column col_num
      grid_contents = @puzzle.get_grid grid_num

      new_value = nil
      value.possible_values.each do |v|
        @logger.debug "\tChecking possible value: #{v}"
        ri = row_contents.select{|rc| rc.possible_values.include? v}.length# == 1 # including ourself
        @logger.debug "\t#{ri} elegible items in this row."
        ci = col_contents.select{|cc| cc.possible_values.include? v}.length# == 1 # including ourself
        @logger.debug "\t#{ci} elegible items in this column."
        gi = grid_contents.select{|gc| gc.possible_values.include? v}.length# == 1 # including ourself
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
