class SudokuError < StandardError
end

class UnsolvableError < SudokuError
  def initialize(msg="Unsolvable")
    super
  end
end

class ImpossibleValueError < SudokuError
  def initialize(msg="Impossible value")
    super
  end
end

class InputDataError < SudokuError
  def initialize(msg="Invalid input data")
    super
  end
end
