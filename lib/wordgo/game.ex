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
  def create_empty_board(size, num_bonus \\ 0) do
    Board.new(size) |> Board.add_bonus(num_bonus)
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
      # Handle either Player struct or string
      player_id =
        case player do
          %Player{} -> player.name
          # Assume it's already a string identifier
          _ -> player
        end

      # Create a new piece and place it on the board
      piece = Piece.new(x, y, player_id, word)
      updated_board = Board.place_piece(board, piece)
      {:ok, updated_board}
    end
  end

  @doc """
  Gets all pieces for a specific player from the board.

  ## Examples

      iex> get_player_words(board, player)
      ["word1", "word2"]
  """
  def get_player_words(board, player) do
    # Handle either Player struct or string
    player_id =
      case player do
        %Player{} -> player.name
        # Assume it's already a string identifier
        _ -> player
      end

    board.pieces
    |> Enum.filter(fn piece -> piece.player == player_id end)
    |> Enum.map(fn piece -> piece.word end)
  end

  @doc """
  Calculates score for a player based on the Board's scoring mechanism.

  ## Examples

      iex> calculate_player_score(board, player)
      15
  """
  def calculate_player_score(board, player) do
    # Handle either Player struct or string
    player_id =
      case player do
        %Player{} -> player.name
        # Assume it's already a string identifier
        _ -> player
      end

    # Use the Board's scoring mechanism
    score_map = Board.score(board)

    # Find the player's score from the score map
    # Board.score returns a list of {player, score} tuples
    case Enum.find(score_map, fn {p, _score} -> p == player_id end) do
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
    # Handle either Player struct or string
    player_id =
      case player do
        %Player{} -> player.name
        # Assume it's already a string identifier
        _ -> player
      end

    # Get all pieces for the player
    player_pieces =
      board.pieces
      |> Enum.filter(fn piece -> piece.player == player_id end)

    # Use Board.get_groups to find all connected groups
    groups = Board.get_groups(player_pieces)

    groups
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
    # Handle either Player struct or string
    player_id =
      case player do
        %Player{} -> player.name
        # Assume it's already a string identifier
        _ -> player
      end

    # Get all groups for the player using the normalized player_id
    groups = get_player_groups(board, player_id)

    # Calculate score for each group
    group_scores =
      Enum.map(groups, fn group ->
        score = Board.score_group(group, board)

        {group, score}
      end)

    group_scores
  end
end
