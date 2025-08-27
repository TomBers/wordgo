defmodule Wordgo.Game.Player do
  defstruct name: nil

  def new(name) do
    %__MODULE__{name: name}
  end

  # def update_score(player, score) do
  #   %{player | score: score}
  # end
end
