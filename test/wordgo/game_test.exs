defmodule Wordgo.GameTest do
  use ExUnit.Case, async: true

  alias Wordgo.Game
  alias Wordgo.Game.{Board, Piece, Player}

  describe "get_player_groups/2" do
    test "returns empty list when player has no pieces" do
      board = Board.new()
      assert Game.get_player_groups(board, "player1") == []
    end

    test "returns single group when player has one piece" do
      board = Board.new()
      board = Board.place_piece(board, Piece.new(1, 1, "player1", "cat"))

      groups = Game.get_player_groups(board, "player1")

      assert length(groups) == 1
      assert length(List.first(groups)) == 1
      assert List.first(List.first(groups)).word == "cat"
    end

    test "returns single group when player has connected pieces" do
      board = Board.new()
      board = Board.place_piece(board, Piece.new(1, 1, "player1", "cat"))
      board = Board.place_piece(board, Piece.new(1, 2, "player1", "dog"))
      board = Board.place_piece(board, Piece.new(1, 3, "player1", "fish"))

      groups = Game.get_player_groups(board, "player1")

      assert length(groups) == 1
      assert length(List.first(groups)) == 3

      words = List.first(groups) |> Enum.map(& &1.word) |> Enum.sort()
      assert words == ["cat", "dog", "fish"]
    end

    test "returns multiple groups when player has disconnected pieces" do
      board = Board.new()
      # First group - horizontal connection
      board = Board.place_piece(board, Piece.new(1, 1, "player1", "cat"))
      board = Board.place_piece(board, Piece.new(1, 2, "player1", "dog"))

      # Second group - disconnected
      board = Board.place_piece(board, Piece.new(5, 5, "player1", "fish"))

      groups = Game.get_player_groups(board, "player1")

      assert length(groups) == 2

      # Sort groups by size for consistent testing
      groups = Enum.sort_by(groups, &length/1, :desc)

      # First group should have 2 pieces
      assert length(List.first(groups)) == 2
      first_group_words = List.first(groups) |> Enum.map(& &1.word) |> Enum.sort()
      assert first_group_words == ["cat", "dog"]

      # Second group should have 1 piece
      assert length(Enum.at(groups, 1)) == 1
      assert Enum.at(Enum.at(groups, 1), 0).word == "fish"
    end

    test "ignores pieces from other players" do
      board = Board.new()
      # player1 pieces
      board = Board.place_piece(board, Piece.new(1, 1, "player1", "cat"))
      board = Board.place_piece(board, Piece.new(1, 2, "player1", "dog"))

      # player2 pieces (one connected to player1's group)
      board = Board.place_piece(board, Piece.new(1, 3, "player2", "fish"))
      board = Board.place_piece(board, Piece.new(5, 5, "player2", "bird"))

      # Get player1's groups
      groups = Game.get_player_groups(board, "player1")

      assert length(groups) == 1
      assert length(List.first(groups)) == 2

      # Ensure no player2 pieces are included
      Enum.each(List.flatten(groups), fn piece ->
        assert piece.player == "player1"
      end)
    end
  end

  describe "get_player_groups_with_scores/2" do
    test "returns groups with their scores" do
      board = Board.new()
      # First group - two connected pieces
      board = Board.place_piece(board, Piece.new(1, 1, "player1", "cat"))
      board = Board.place_piece(board, Piece.new(1, 2, "player1", "dog"))

      # Second group - single piece
      board = Board.place_piece(board, Piece.new(5, 5, "player1", "fish"))

      group_scores = Game.get_player_groups_with_scores(board, "player1")

      assert length(group_scores) == 2

      # Each entry should be a tuple {group, score}
      Enum.each(group_scores, fn {group, score} ->
        assert is_list(group)
        assert is_number(score)
      end)

      # Sum of group scores should equal total player score
      total_from_groups = Enum.reduce(group_scores, 0, fn {_group, score}, acc -> acc + score end)
      total_score = Game.calculate_player_score(board, "player1")

      assert total_from_groups == total_score
    end
  end

  describe "place_word/4" do
    test "places a piece on the board" do
      board = Board.new()
      {:ok, updated_board} = Game.place_word(board, {1, 1}, "cat", "player1")

      assert length(updated_board.pieces) == 1
      assert List.first(updated_board.pieces).word == "cat"
    end

    test "returns error when position is occupied" do
      board = Board.new()
      {:ok, board} = Game.place_word(board, {1, 1}, "cat", "player1")

      result = Game.place_word(board, {1, 1}, "dog", "player2")

      assert result == {:error, "Position is already occupied"}
    end
  end
end
