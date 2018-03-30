#!/usr/bin/env ruby

PUZZLE_WIDTH = 9
PUZZLE_DISPLAY_WIDTH = 25
SORTED_NUMBERS = [1,2,3,4,5,6,7,8,9]

class SudokuPuzzle
  def initialize(data)
    @data = data.delete("\r\n").split("").map(&:to_i)
    print_puzzle
  end

  def print_puzzle
    @data.each_with_index do |char,index|
      print_horizontal_line if (index%27 == 0)
      print "| " if (index%3 == 0)
      print char==0 ? "-" : "#{char}"
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
    get_row(num).sort == SORTED_NUMBERS 
  end

  def validate_column(num)
    get_column(num).sort == SORTED_NUMBERS
  end

  def validate_grid(num)
    get_grid(num).sort == SORTED_NUMBERS
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
  end
  solver = SudokuSolver.new ARGV[0]
  solver.solve
end
