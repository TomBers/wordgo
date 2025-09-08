defmodule Wordgo.Game.BoardTest do
  use ExUnit.Case, async: true

  alias Wordgo.Game.Board
  alias Wordgo.Game.Piece

  describe "get_groups/1" do
    test "groups connected pieces correctly" do
      # Create a few pieces with two distinct groups
      pieces = [
        # Group 1: connected horizontally and vertically (at 1,1 and 1,2)
        Piece.new(1, 1, "player1", "cat"),
        Piece.new(1, 2, "player1", "dog"),

        # Group 2: isolated piece
        Piece.new(5, 5, "player1", "bird")
      ]

      # Get the groups
      groups = Board.get_groups(pieces)

      # We expect 2 groups
      assert length(groups) == 2

      # Check if groups have the expected sizes
      group_sizes = groups |> Enum.map(&length/1) |> Enum.sort()
      assert group_sizes == [1, 2]

      # Find the larger group and verify its contents
      larger_group = groups |> Enum.find(fn group -> length(group) == 2 end)

      # Check that the larger group contains the expected words
      words_in_larger_group = larger_group |> Enum.map(& &1.word) |> Enum.sort()
      assert words_in_larger_group == ["cat", "dog"]
    end

    test "handles empty input" do
      assert Board.get_groups([]) == []
    end

    test "each piece forms its own group when no connections exist" do
      pieces = [
        Piece.new(1, 1, "player1", "cat"),
        Piece.new(3, 3, "player1", "dog"),
        Piece.new(5, 5, "player1", "fish")
      ]

      groups = Board.get_groups(pieces)

      assert length(groups) == 3
      assert Enum.all?(groups, fn group -> length(group) == 1 end)
    end
  end

  describe "integration with scoring" do
    test "scores are calculated correctly for groups" do
      # Create a board with two groups
      board =
        Board.new()
        |> Board.place_piece(Piece.new(1, 1, "player1", "cat"))
        |> Board.place_piece(Piece.new(1, 2, "player1", "dog"))
        |> Board.place_piece(Piece.new(5, 5, "player1", "bird"))

      # Get player pieces
      player_pieces = Enum.filter(board.pieces, &(&1.player == "player1"))

      # Get groups
      groups = Board.get_groups(player_pieces)

      # Calculate scores for individual groups
      group_scores = Enum.map(groups, &Board.score_group/1)

      # The total score should equal the sum of group scores
      total_score = Enum.sum(group_scores)

      # Verify against the traditional scoring method
      [{_, score_from_score_function}] = Board.score(board)

      assert total_score == score_from_score_function
    end
  end
end
