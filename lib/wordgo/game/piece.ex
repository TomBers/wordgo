defmodule Wordgo.Game.Piece do
  defstruct x: nil, y: nil, player: nil, word: nil

  def new(x, y, player, word) do
    %__MODULE__{x: x, y: y, player: player, word: word}
  end

  def move(piece, x, y) do
    %{piece | x: x, y: y}
  end

  def set_word(piece, word) do
    %{piece | word: word}
  end
end
