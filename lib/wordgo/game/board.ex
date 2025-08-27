defmodule Wordgo.Game.Board do
  defstruct x_size: 15, y_size: 15, pieces: []

  def new(size \\ 15) do
    %__MODULE__{x_size: size, y_size: size, pieces: []}
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

  defp score_pieces(pieces) do
    # Build a map of pieces by their coordinates for quick lookup
    pieces_by_coords = Enum.into(pieces, %{}, fn piece -> {{piece.x, piece.y}, piece} end)

    # Track visited pieces to avoid double counting
    visited = MapSet.new()

    # Find all connected groups and calculate their scores
    {total_score, _} =
      Enum.reduce(pieces, {0, visited}, fn piece, {score_acc, visited_acc} ->
        # Skip pieces we've already processed
        if MapSet.member?(visited_acc, {piece.x, piece.y}) do
          {score_acc, visited_acc}
        else
          # Find all connected pieces starting from this piece
          {group, new_visited} = find_connected_group(piece, pieces_by_coords, visited_acc)

          group_score = score_group(group)

          # Add to total score and mark these pieces as visited
          {score_acc + group_score, new_visited}
        end
      end)

    total_score
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
        if Map.has_key?(pieces_by_coords, adj_coords) and
             not MapSet.member?(visited_acc, adj_coords) do
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

  defp score_group(group) do
    # Calculate score for this group (size² because each piece is worth the group size)
    IO.inspect(group, label: "Group")
    group_size = length(group)
    group_score = group_size * group_size
    group_score
  end
end
