defmodule WordgoWeb.GameLive.Helpers do
  @moduledoc """
  Provides helper functions for the GameLive view.

  This module contains utility functions for calculating scores, determining player
  turns, and assigning colors to players.
  """

  @doc """
  Determines the next player in the turn rotation.
  """
  def next_player(players, current) do
    cond do
      players == [] ->
        current

      true ->
        idx = Enum.find_index(players, &(&1 == current)) || 0
        Enum.at(players, rem(idx + 1, length(players)))
    end
  end

  @doc """
  Assigns a consistent color to a player based on their name.
  """
  def player_color(name) when is_binary(name) do
    colors = [
      "bg-red-500",
      "bg-blue-500",
      "bg-green-500",
      "bg-yellow-500",
      "bg-purple-500",
      "bg-pink-500"
    ]

    hash = :erlang.phash2(name, length(colors))
    Enum.at(colors, hash)
  end

  @doc """
  Builds a map of player names to their assigned colors.
  """
  def build_player_colors(players) do
    Enum.reduce(players || [], %{}, fn name, acc ->
      Map.put(acc, name, player_color(name))
    end)
  end
end
