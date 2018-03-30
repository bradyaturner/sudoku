#!/usr/bin/env ruby

PUZZLE_WIDTH = 9
PUZZLE_DISPLAY_WIDTH = 25

class SudokuPuzzle
  def initialize(data)
    @data = data.delete("\r\n").split("")
    print_puzzle
  end

  def print_puzzle
    puts "Puzzle: #{@data.inspect}"
    @data.each_with_index do |char,index|
      char = "-" if char == "0"
      print_horizontal_line if (index%27 == 0)
      if (index%3 == 0)
        print "| "
      end
      print "#{char}"
      print (index+1)%9==0 ? " |\n" : " "
    end
    print_horizontal_line


    puts "(5,5)"
    puts row_value(5,5)
    puts column_value(5,5)
    puts value_at(5,5)
    puts ""

    puts "(3,7)"
    puts row_value(3,7)
    puts column_value(7,3)
    puts value_at(3,7)
    puts ""
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
    puts @file
    @puzzles = []
    @file.each_line do |line|
      @puzzles << SudokuPuzzle.new(line)
    end
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
