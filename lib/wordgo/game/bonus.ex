defmodule Wordgo.Game.Bonus do
  defstruct x: nil, y: nil, name: "", symbol: "", value: 1

  def gen_piece(poss \\ {1, 1}) do
    Enum.random([times_2(poss), times_4(poss)])
  end

  def times_2({x, y}) do
    %__MODULE__{x: x, y: y, name: "Double", symbol: "x2", value: 2}
  end

  def times_4({x, y}) do
    %__MODULE__{x: x, y: y, name: "Quad", symbol: "x4", value: 4}
  end
end
