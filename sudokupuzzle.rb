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
  attr_reader :value, :initial_value, :candidates, :row,
    :col, :grid
  def initialize(initial_value, row, col, grid, candidates=nil)
    @initial_value = initial_value
    @value = initial_value
    @row = row
    @col = col
    @grid = grid
    if @initial_value == 0 && candidates == nil
      @candidates = Array.new(SORTED_NUMBERS)
    elsif @initial_value == 0
      @candidates = candidates
      @initial_value = @value = @candidates.first if @candidates.length == 1
    else
      @candidates = [initial_value]
    end
    @logger = Logger.new(STDERR)
    @logger.level = LoggerConfig::SUDOKUCELL_LEVEL
  end

  def ==(b)
    @value == b.value &&
      @row == b.row &&
      @col == b.col &&
      @grid == b.grid &&
      @candidates == b.candidates
  end

  def solved?
    (@value != 0) && (@candidates.length == 1)
  end

  def set_value(v)
    raise ImpossibleValueError, "Not candidate value! #{v}, #{@candidates.inspect}" if !@candidates.include?(v)
    @value = v
    @candidates = [v]
  end

  # TODO get rid of this method, shouldn't be exposed outside this class
  # need it now for resetting state when coming out of recursive call for brute forcing
  def set_candidates(pv)
    @candidates = pv
    @value = @initial_value
  end

  def update_value
    if @candidates.length == 1
      @value = @candidates.first
    end
  end

  def remove_candidate(v) remove_candidates [v] end

  def remove_candidates(values)
    @logger.debug "remove_candidates: #{values.inspect}"
    @candidates -= values
    if @candidates.length <= 0
      @logger.debug "Attempting to remove candidate values #{values.inspect} from cell (#{@row},#{@col})"
      raise ImpossibleValueError, "No candidate values!"
    end
  end

  def coords
    [row,col]
  end

  def to_s
    "Cell containing #{@value} at pos (#{@row},#{@col}) in grid ##{@grid}"
  end

  def serialize
    "#{@candidates.join(',')}:#{@value}"
  end
end

class SudokuPuzzle
  attr_reader :cells
  def initialize(data, with_candidates=false)
    @cells = []
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
      @cells << SudokuCell.new(v,row,col,grid)
    end
  end

  def import_with_candidates(data)
    data.split(";").each_with_index do |c,i|
      row, col, grid = index_to_coords i
      cd, vd = c.split(":")
      value = vd.to_i
      candidates = cd.split(',').map(&:to_i)
      @cells << SudokuCell.new(value,row,col,grid,candidates)
    end
  end

  def index_to_coords(i)
    row = i/PUZZLE_WIDTH
    col = i%PUZZLE_WIDTH
    grid = ((row/GRID_WIDTH)*GRID_WIDTH) + (col/GRID_WIDTH)
    [row,col,grid]
  end

  def print_puzzle(initial_state=false)
    @cells.each_with_index do |value,index|
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
    @cells[(num*PUZZLE_WIDTH)..(num*PUZZLE_WIDTH)+8]
  end

  def get_column_values(num)
    get_column(num).collect{|v| v.value}
  end

  def get_column(num)
    col = []
    @cells.each_with_index {|val,index| col << val if (index%PUZZLE_WIDTH == num)}
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
    @cells[(row * PUZZLE_WIDTH) + pos]
  end

  def column_value(column,pos)
    @cells[(pos * PUZZLE_WIDTH) + column]
  end

  def serialize
    @cells.collect{|v| v.value}.join
  end

  def serialize_with_candidates
    @cells.collect{|v| v.serialize }.join(";")
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


