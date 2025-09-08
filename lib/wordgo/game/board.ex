defmodule Wordgo.Game.Board do
  alias Wordgo.WordToVec.GetScore
  defstruct x_size: 9, y_size: 9, pieces: []

  def new(size \\ 9) do
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

  def get_groups(pieces) do
    IO.inspect(pieces, label: "Input pieces to get_groups")

    # Build a map of pieces by their coordinates for quick lookup
    pieces_by_coords = Enum.into(pieces, %{}, fn piece -> {{piece.x, piece.y}, piece} end)
    IO.inspect(pieces_by_coords, label: "Pieces by coordinates map")

    # Track visited pieces to avoid double counting
    visited = MapSet.new()

    # Find all connected groups
    result =
      Enum.reduce(pieces, {[], visited}, fn piece, {groups_acc, visited_acc} ->
        # Skip pieces we've already processed
        if MapSet.member?(visited_acc, {piece.x, piece.y}) do
          IO.puts("Skipping already visited piece at (#{piece.x}, #{piece.y})")
          {groups_acc, visited_acc}
        else
          IO.puts("Processing piece at (#{piece.x}, #{piece.y})")
          # Find all connected pieces starting from this piece
          {group, new_visited} = find_connected_group(piece, pieces_by_coords, visited_acc)
          IO.inspect(group, label: "Found group starting from (#{piece.x}, #{piece.y})")

          # Add to groups and mark these pieces as visited
          {[group | groups_acc], new_visited}
        end
      end)

    groups = elem(result, 0)
    IO.inspect(groups, label: "Final groups from get_groups")
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
    IO.puts("Finding connected group for piece at #{inspect(coords)}, word: #{piece.word}")

    # Mark current piece as visited
    visited = MapSet.put(visited, coords)

    # Check all adjacent positions (up, down, left, right)
    adjacent_coords = [
      {piece.x + 1, piece.y},
      {piece.x - 1, piece.y},
      {piece.x, piece.y + 1},
      {piece.x, piece.y - 1}
    ]

    IO.inspect(adjacent_coords, label: "Adjacent coordinates to check")

    # Find valid adjacent pieces that haven't been visited yet
    {connected_pieces, updated_visited} =
      Enum.reduce(adjacent_coords, {[], visited}, fn adj_coords, {pieces_acc, visited_acc} ->
        has_key = Map.has_key?(pieces_by_coords, adj_coords)
        already_visited = MapSet.member?(visited_acc, adj_coords)

        IO.puts(
          "Checking adjacent #{inspect(adj_coords)}: exists=#{has_key}, visited=#{already_visited}"
        )

        if has_key and not already_visited do
          # This is a valid adjacent piece that we haven't visited
          adj_piece = Map.get(pieces_by_coords, adj_coords)
          IO.puts("Found connected piece at #{inspect(adj_coords)}, word: #{adj_piece.word}")

          # Recursively find all pieces connected to this one
          {group, new_visited} = find_connected_group(adj_piece, pieces_by_coords, visited_acc)

          # Combine results
          {pieces_acc ++ group, new_visited}
        else
          {pieces_acc, visited_acc}
        end
      end)

    IO.puts(
      "Connected pieces for #{piece.word} at #{inspect(coords)}: #{length(connected_pieces)}"
    )

    # Return this piece plus all connected pieces
    {[piece | connected_pieces], updated_visited}
  end

  def score_group(group) do
    # Calculate score for this group (size² because each piece is worth the group size)
    IO.inspect(group, label: "Group")
    # TODO: Calculate the word similarity of the group
    # See Wordgo.WordToVec.GetScore
    group_size = length(group)
    group_size * GetScore.score_group(group |> Enum.map(& &1.word))
  end
end
