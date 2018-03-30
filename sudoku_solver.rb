#!/usr/bin/env ruby

PUZZLE_WIDTH = 9
PUZZLE_DISPLAY_WIDTH = 25
SORTED_NUMBERS = [1,2,3,4,5,6,7,8,9]
EMPTY_CHAR = "-"

class SudokuValue
  attr_reader :value
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

  def remove_possible_value(val)
    @possible_values.delete val
  end

  def to_s
    @value == 0 ? EMPTY_CHAR : @value
  end
end

class SudokuPuzzle
  def initialize(data)
    @data = []
    data.delete("\r\n").split("").map(&:to_i).each do |v|
      @data << SudokuValue.new(v)
    end
    print_puzzle
  end

  def print_puzzle
    @data.each_with_index do |value,index|
      print_horizontal_line if (index%27 == 0)
      print "| " if (index%3 == 0)
      print value.to_s
      print (index+1)%9==0 ? " |\n" : " "
    end
    print_horizontal_line

    puts "Solved? #{solved?}"
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

  def validate_row(num)
    get_row(num).collect{|v| v.value}.sort == SORTED_NUMBERS
  end

  def validate_column(num)
    get_column(num).collect{|v| v.value}.sort == SORTED_NUMBERS
  end

  def validate_grid(num)
    get_grid(num).collect{|v| v.value}.sort == SORTED_NUMBERS
  end

  def get_row(num)
    @data[(num*PUZZLE_WIDTH)..(num*PUZZLE_WIDTH)+8]
  end

  def get_column(num)
    col = []
    @data.each_with_index {|val,index| col << val if (index%PUZZLE_WIDTH == num)}
    col 
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
end

class SudokuSolver
  def initialize(file)
    @file = File.read(file)
    @puzzles = []
    @file.each_line {|line| @puzzles << SudokuPuzzle.new(line)}
  end

  def solve
  end
end

if __FILE__==$0
  if !ARGV[0]
    STDERR.puts "USAGE: #{__FILE__} [FILE]"
    exit 0
  end
  solver = SudokuSolver.new ARGV[0]
  solver.solve
end
