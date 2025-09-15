defmodule Wordgo.Game.Board do
  alias Wordgo.Game.Bonus
  alias Wordgo.WordToVec.GetScore
  defstruct x_size: 9, y_size: 9, pieces: [], bonus: []

  def new(size \\ 9) do
    %__MODULE__{x_size: size, y_size: size, pieces: [], bonus: []}
  end

  def add_bonus(board, num \\ 2) do
    range = 0..(board.x_size - 1)
    # Generate all possible coordinates
    all_coords = for x <- range, y <- range, do: {x, y}
    available_coords = all_coords
    # Shuffle and take up to num unique, unoccupied coordinates
    selected_coords = available_coords |> Enum.shuffle() |> Enum.take(num)
    bonus = Enum.map(selected_coords, fn coord -> Bonus.gen_piece(coord) end)
    %{board | bonus: bonus ++ board.bonus}
  end

  def place_piece(board, piece) do
    if piece.x > board.x_size || piece.y > board.y_size do
      board
    else
      %{board | pieces: [piece | board.pieces]}
    end
  end

  def score(board) do
    player_pieces =
      board.pieces
      |> Enum.sort_by(& &1.player)
      |> Enum.chunk_by(& &1.player)

    Enum.zip(
      Enum.map(player_pieces, &List.first(&1).player),
      Enum.map(player_pieces, &score_pieces(&1))
    )
  end

  def get_groups(pieces) do
    # Build a map of pieces by their coordinates for quick lookup
    pieces_by_coords = Enum.into(pieces, %{}, fn piece -> {{piece.x, piece.y}, piece} end)

    # Track visited pieces to avoid double counting
    visited = MapSet.new()

    # Find all connected groups
    result =
      Enum.reduce(pieces, {[], visited}, fn piece, {groups_acc, visited_acc} ->
        # Skip pieces we've already processed
        if MapSet.member?(visited_acc, {piece.x, piece.y}) do
          {groups_acc, visited_acc}
        else
          # Find all connected pieces starting from this piece
          {group, new_visited} = find_connected_group(piece, pieces_by_coords, visited_acc)

          # Add to groups and mark these pieces as visited
          {[group | groups_acc], new_visited}
        end
      end)

    groups = elem(result, 0)

    groups
  end

  defp score_pieces(pieces) do
    # Get all connected groups
    groups = get_groups(pieces)

    # Calculate and sum up scores for all groups
    Enum.reduce(groups, 0, fn group, acc ->
      acc + score_group(group)
    end)
  end

  # Recursive function to find all connected pieces using DFS
  defp find_connected_group(piece, pieces_by_coords, visited) do
    coords = {piece.x, piece.y}

    # Mark current piece as visited
    visited = MapSet.put(visited, coords)

    # Check all adjacent positions (up, down, left, right)
    adjacent_coords = [
      {piece.x + 1, piece.y},
      {piece.x - 1, piece.y},
      {piece.x, piece.y + 1},
      {piece.x, piece.y - 1}
    ]

    # Find valid adjacent pieces that haven't been visited yet
    {connected_pieces, updated_visited} =
      Enum.reduce(adjacent_coords, {[], visited}, fn adj_coords, {pieces_acc, visited_acc} ->
        has_key = Map.has_key?(pieces_by_coords, adj_coords)
        already_visited = MapSet.member?(visited_acc, adj_coords)

        if has_key and not already_visited do
          # This is a valid adjacent piece that we haven't visited
          adj_piece = Map.get(pieces_by_coords, adj_coords)

          # Recursively find all pieces connected to this one
          {group, new_visited} = find_connected_group(adj_piece, pieces_by_coords, visited_acc)

          # Combine results
          {pieces_acc ++ group, new_visited}
        else
          {pieces_acc, visited_acc}
        end
      end)

    # Return this piece plus all connected pieces
    {[piece | connected_pieces], updated_visited}
  end

  def score_group(group) do
    # Calculate score for this group (size² because each piece is worth the group size)

    # See Wordgo.WordToVec.GetScore
    group_size = length(group)
    group_size * GetScore.score_group(group |> Enum.map(& &1.word))
  end

  # === Adjacency and position helpers (for AI heuristics) ===

  # Returns true if the coordinate is within the board bounds
  def in_bounds?({x, y}, %__MODULE__{x_size: xs, y_size: ys}) do
    x >= 0 and y >= 0 and x < xs and y < ys
  end

  # Returns the 4-neighborhood (up, down, left, right) within bounds
  def neighbors({x, y}, %__MODULE__{} = board) do
    [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]
    |> Enum.filter(&in_bounds?(&1, board))
  end

  # Returns a list of occupied positions as {x, y}
  def occupied_positions(%__MODULE__{} = board) do
    Enum.map(board.pieces, &{&1.x, &1.y})
  end

  # Returns a list of empty positions as {x, y}
  def empty_positions(%__MODULE__{} = board) do
    occupied = MapSet.new(occupied_positions(board))

    for y <- 0..(board.y_size - 1),
        x <- 0..(board.x_size - 1),
        not MapSet.member?(occupied, {x, y}),
        do: {x, y}
  end

  # Returns a list of {x, y} for the given player's pieces
  def player_piece_coords(%__MODULE__{} = board, player) do
    board.pieces
    |> Enum.filter(&(&1.player == player))
    |> Enum.map(&{&1.x, &1.y})
  end
end
