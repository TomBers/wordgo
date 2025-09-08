defmodule Wordgo.Game do
  @moduledoc """
  The Game context coordinates interactions between game components
  including Board, Piece, and Player.
  """

  alias Wordgo.Game.{Board, Piece, Player}

  @doc """
  Creates a new empty board with the specified size.

  Returns a Board struct.
  """
  def create_empty_board(size) do
    Board.new(size)
  end

  @doc """
  Creates a new player with default values.

  ## Examples

      iex> create_player("player1", "Player One")
      %Player{name: "Player One"}

  """
  def create_player(_id, name) do
    Player.new(name)
  end

  @doc """
  Places a piece on the board at the specified coordinates.

  Returns {:ok, updated_board} if successful, or {:error, reason} if the position
  is already occupied.

  ## Examples

      iex> place_word(board, {0, 0}, "hello", player)
      {:ok, %Board{}}

  """
  def place_word(board, {x, y}, word, player) do
    # Check if position is already occupied
    if Enum.any?(board.pieces, fn piece -> piece.x == x && piece.y == y end) do
      {:error, "Position is already occupied"}
    else
      # Create a new piece and place it on the board
      piece = Piece.new(x, y, player, word)
      updated_board = Board.place_piece(board, piece)
      {:ok, updated_board}
    end
  end

  @doc """
  Updates placed words list after placing a word.
  In this implementation, we're using the Board's scoring mechanism.

  ## Examples

      iex> update_player_stats(player, "hello", placed_words)
      {updated_player, updated_placed_words}

  """
  def update_player_stats(player, word, placed_words, x, y) do
    # We don't modify the player struct since scoring is handled by Board.score

    # Create a record for the placed word
    placed_word = Piece.new(x, y, player.name, word)

    {player, [placed_word | placed_words]}
  end

  @doc """
  Creates a record for a placed word.

  ## Examples

      iex> create_placed_word_record(1, 2, "hello", "Player One")
      %{x: 1, y: 2, word: "hello", player_name: "Player One"}

  """
  def create_placed_word_record(x, y, word, player_name) do
    Piece.new(x, y, player_name, word)
  end

  @doc """
  Gets all pieces for a specific player from the board.

  ## Examples

      iex> get_player_words(board, player)
      ["word1", "word2"]
  """
  def get_player_words(board, player) do
    board.pieces
    |> Enum.filter(fn piece -> piece.player == player end)
    |> Enum.map(fn piece -> piece.word end)
  end

  @doc """
  Calculates score for a player based on the Board's scoring mechanism.

  ## Examples

      iex> calculate_player_score(board, player)
      15
  """
  def calculate_player_score(board, player) do
    # Use the Board's scoring mechanism
    score_map = Board.score(board)

    # Find the player's score from the score map
    # Board.score returns a list of {player, score} tuples
    case Enum.find(score_map, fn {p, _score} -> p == player end) do
      {_player, score} -> score
      # Return 0 if player not found in score map
      nil -> 0
    end
  end

  @doc """
  Gets all word groups for a player.
  A group consists of connected pieces on the board.

  ## Examples

      iex> get_player_groups(board, "player1")
      [
        [%Piece{...}, %Piece{...}],  # First group
        [%Piece{...}]                # Second group
      ]
  """
  def get_player_groups(board, player) do
    # Get all pieces for the player
    player_pieces =
      board.pieces
      |> Enum.filter(fn piece -> piece.player == player end)

    # Use Board.get_groups to find all connected groups
    Board.get_groups(player_pieces)
  end

  @doc """
  Gets all word groups with their scores for a specific player.
  Returns a list of tuples containing {group, score}.

  ## Examples

      iex> get_player_groups_with_scores(board, "player1")
      [
        {[%Piece{...}, %Piece{...}], 10},  # First group with score
        {[%Piece{...}], 5}                 # Second group with score
      ]
  """
  def get_player_groups_with_scores(board, player) do
    # Get all groups for the player
    groups = get_player_groups(board, player)

    # Calculate score for each group
    Enum.map(groups, fn group ->
      {group, Board.score_group(group)}
    end)
  end
end
