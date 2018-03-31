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
