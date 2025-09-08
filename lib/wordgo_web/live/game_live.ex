defmodule WordgoWeb.GameLive do
  use WordgoWeb, :live_view
  alias Wordgo.Game

  # Define the initial state for the game
  @board_size 6

  @impl true
  def mount(_params, _session, socket) do
    # Create an empty board using the Board module
    empty_board = Game.create_empty_board(@board_size)

    # Initialize a test player using the Player module
    # We use a string ID but the scoring system only uses the player struct
    test_player = Game.create_player("player1", "Test Player")

    # Initialize with empty board and player
    socket =
      socket
      |> assign(:board, empty_board)
      |> assign(:board_size, @board_size)
      |> assign(:current_player, test_player)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:placed_words, [])
      |> assign(:word_groups, [])
      |> assign(:group_scores, [])
      # Add current_scope for the layout
      |> assign(:current_scope, "game")

    # Send ourselves a message after mount to update groups
    if connected?(socket) do
      send(self(), :update_groups)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:update_groups, socket) do
    # Get the current board and player
    board = socket.assigns.board
    player_name = socket.assigns.current_player.name

    # Get word groups and their scores
    word_groups = Game.get_player_groups(board, player_name)
    group_scores = Game.get_player_groups_with_scores(board, player_name)

    socket =
      socket
      |> assign(:word_groups, word_groups)
      |> assign(:group_scores, group_scores)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-position", %{"x" => x, "y" => y}, socket) do
    x = String.to_integer(x)
    y = String.to_integer(y)

    # Check if the position is already occupied
    board = socket.assigns.board

    # Check if position is occupied by looking at board pieces
    if Enum.any?(board.pieces, fn piece -> piece.x == x && piece.y == y end) do
      {:noreply, assign(socket, :error_message, "That position is already occupied")}
    else
      {:noreply, assign(socket, :selected_position, {x, y})}
    end
  end

  @impl true
  def handle_event("place-word", %{"word" => word}, socket) do
    word = String.trim(word)

    # Simple validation: ensure word is not empty and has reasonable length
    cond do
      word == "" ->
        {:noreply, assign(socket, :error_message, "Please enter a word")}

      String.length(word) > 20 ->
        {:noreply, assign(socket, :error_message, "Word is too long (maximum 20 characters)")}

      true ->
        # Get the selected position
        case socket.assigns.selected_position do
          nil ->
            {:noreply,
             assign(socket, :error_message, "Please select a position on the board first")}

          {x, y} ->
            # Place the word on the board
            case Game.place_word(
                   socket.assigns.board,
                   {x, y},
                   word,
                   socket.assigns.current_player.name
                 ) do
              {:ok, updated_board} ->
                # Update player info and placed words list
                current_player = socket.assigns.current_player

                {_updated_player, updated_placed_words} =
                  Game.update_player_stats(
                    current_player,
                    word,
                    socket.assigns.placed_words,
                    x,
                    y
                  )

                # Get word groups and their scores
                word_groups = Game.get_player_groups(updated_board, current_player.name)
                IO.inspect(word_groups, label: "Word Groups")

                # Get updated groups and scores using the Game module functions
                word_groups = Game.get_player_groups(updated_board, current_player.name)

                group_scores =
                  Game.get_player_groups_with_scores(updated_board, current_player.name)

                socket =
                  socket
                  |> assign(:board, updated_board)
                  # Keep the same player reference
                  |> assign(:current_player, current_player)
                  |> assign(:selected_position, nil)
                  |> assign(:current_word, "")
                  |> assign(:error_message, nil)
                  |> assign(:placed_words, updated_placed_words)
                  |> assign(:word_groups, word_groups)
                  |> assign(:group_scores, group_scores)

                IO.puts("Word groups in socket: #{inspect(socket.assigns.word_groups)}")
                IO.puts("Group scores in socket: #{inspect(socket.assigns.group_scores)}")

                {:noreply, socket}

              {:error, message} ->
                {:noreply, assign(socket, :error_message, message)}
            end
        end
    end
  end

  @impl true
  def handle_event("reset-game", _params, socket) do
    # Create a new empty board using the Board module
    empty_board = Game.create_empty_board(@board_size)
    IO.puts("Reset game - created empty board")

    # Reset the player using the Player module
    test_player = Game.create_player("player1", "Test Player")

    socket =
      socket
      |> assign(:board, empty_board)
      |> assign(:current_player, test_player)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:placed_words, [])
      |> assign(:word_groups, [])
      |> assign(:group_scores, [])
      |> assign(:current_scope, "game")

    # Clear the board but also send an update message to refresh groups
    if connected?(socket) do
      send(self(), :update_groups)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update-word", %{"word" => word}, socket) do
    {:noreply, assign(socket, :current_word, word)}
  end

  defp round_score(score) when is_number(score) do
    if score > 0 do
      Float.round(score, 2)
    else
      0
    end
  end

  defp round_score(score) do
    score
  end
end
