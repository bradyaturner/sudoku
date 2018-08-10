require './exceptions'
require './loggerconfig'

require 'logger'

# not sure everything works with other sizes
PUZZLE_WIDTH = 9
GRID_WIDTH = 3

PUZZLE_DISPLAY_WIDTH = 25
SORTED_NUMBERS = [1,2,3,4,5,6,7,8,9]
EMPTY_CHAR = "-"

class SudokuCell
  attr_reader :value, :initial_value, :possible_values, :row,
    :col, :grid
  def initialize(initial_value, row, col, grid, possible_values=nil)
    @initial_value = initial_value
    @value = initial_value
    @row = row
    @col = col
    @grid = grid
    if @initial_value == 0 && possible_values == nil
      @possible_values = Array.new(SORTED_NUMBERS)
    elsif @initial_value == 0
      @possible_values = possible_values
      @initial_value = @value = @possible_values.first if @possible_values.length == 1
    else
      @possible_values = [initial_value]
    end
    @logger = Logger.new(STDERR)
    @logger.level = LoggerConfig::SUDOKUCELL_LEVEL
  end

  def ==(b)
    @value == b.value &&
      @row == b.row &&
      @col == b.col &&
      @grid == b.grid &&
      @possible_values == b.possible_values
  end

  def solved?
    (@value != 0) && (@possible_values.length == 1)
  end

  def set_value(v)
    raise ImpossibleValueError, "Not possible value! #{v}, #{@possible_values.inspect}" if !@possible_values.include?(v)
    @value = v
    @possible_values = [v]
  end

  def set_possible_values(pv)
    @possible_values = pv
    if @possible_values.length == 1
      @value = @possible_values.first
    else
      @value = @initial_value
    end
  end

  def remove_possible_values(values)
    if @row == 8 && @col == 4 && values.include?(3)
      puts "TRYING TO REMOVE '3' from (8,4)"
      exit
    end
    @possible_values -= values
    if @possible_values.length == 1
      @value = @possible_values.first
    elsif @possible_values.length <= 0
      @logger.debug "Attempting to remove candidate values #{values.inspect} from cell (#{@row},#{@col})"
      raise ImpossibleValueError, "No possible values!"
    end
  end

  def to_s
    "Cell containing #{@value} at pos (#{@row},#{@col}) in grid ##{@grid}"
  end
end

class SudokuPuzzle
  attr_reader :data
  def initialize(data, with_candidates=false)
    @data = []
    data.delete!("\r\n")
    if !with_candidates
    raise InputDataError, "Invalid input puzzle size: #{data.length}" if data.length != PUZZLE_WIDTH ** 2
      import_puzzle data
    else
      import_with_candidates data
    end
  end

  def import_puzzle(data)
    data.split("").map(&:to_i).each_with_index do |v,i|
      row, col, grid = index_to_coords(i)
      @data << SudokuCell.new(v,row,col,grid)
    end
  end

  def import_with_candidates(data)
    data.split(";").each_with_index do |v,i|
      row, col, grid = index_to_coords i
      values = v.split(',').map(&:to_i)
      @data << SudokuCell.new(0,row,col,grid,values)
    end
  end

  def index_to_coords(i)
    row = i/PUZZLE_WIDTH
    col = i%PUZZLE_WIDTH
    grid = ((row/GRID_WIDTH)*GRID_WIDTH) + (col/GRID_WIDTH)
    [row,col,grid]
  end

  def print_puzzle(initial_state=false)
    @data.each_with_index do |value,index|
      print_horizontal_line if (index%27 == 0)
      print "| " if (index%3 == 0)
      char = initial_state ? value.initial_value : value.value
      print char == 0 ? EMPTY_CHAR : char
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

  def serialize_with_candidates
    @data.collect{|v| v.possible_values.join(',')}.join(";")
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


