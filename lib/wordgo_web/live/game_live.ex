defmodule WordgoWeb.GameLive do
  use WordgoWeb, :live_view
  alias Wordgo.Game
  alias Wordgo.Game.Initialize
  alias Wordgo.Game.AI
  alias Phoenix.PubSub

  require Logger

  # Define the initial state for the game
  @board_size 6

  @impl true
  def mount(params, _session, socket) do
    # Initialize game session using the Initialize module
    game_assigns = Initialize.initialize_game_session(params, @board_size)

    # Apply all assigns to socket
    socket =
      Enum.reduce(game_assigns, socket, fn
        {:flash, _}, acc -> acc
        {key, value}, acc -> assign(acc, key, value)
      end)

    if connected?(socket) do
      # Handle connected initialization
      messages_to_send = Initialize.handle_connected_initialization(socket.assigns)

      # Send all messages
      Enum.each(messages_to_send, &send(self(), &1))
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
    current_name = socket.assigns.current_player.name

    # Turn-based guard and validation
    cond do
      socket.assigns.current_turn && socket.assigns.current_turn != current_name ->
        {:noreply, assign(socket, :error_message, "It's not your turn")}

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
            # Ensure all words on the board are unique (case-insensitive)
            existing_words =
              socket.assigns.board.pieces
              |> Enum.map(&String.downcase(&1.word))

            if String.downcase(word) in existing_words do
              {:noreply, assign(socket, :error_message, "That word is already on the board")}
            else
              # Place the word on the board
              case Game.place_word(socket.assigns.board, {x, y}, word, current_name) do
                {:ok, updated_board} ->
                  players = socket.assigns.players || [current_name]
                  next_turn = next_player(players, current_name)

                  # Broadcast the move so all subscribers update their state
                  PubSub.broadcast(
                    Wordgo.PubSub,
                    socket.assigns.topic,
                    {:move, %{board: updated_board, next_turn: next_turn}}
                  )

                  # Update local UI (your own groups/scores)
                  word_groups = Game.get_player_groups(updated_board, current_name)
                  group_scores = Game.get_player_groups_with_scores(updated_board, current_name)

                  socket =
                    socket
                    |> assign(:board, updated_board)
                    |> assign(:selected_position, nil)
                    |> assign(:current_word, "")
                    |> assign(:error_message, nil)
                    |> assign(:word_groups, word_groups)
                    |> assign(:group_scores, group_scores)
                    |> assign(:current_turn, next_turn)

                  # If AI is enabled and its turn is next, schedule an AI move on this connection
                  if socket.assigns[:ai_enabled] && next_turn == "AI" do
                    Process.send_after(self(), :ai_move, 1000)
                  end

                  {:noreply, socket}

                {:error, message} ->
                  {:noreply, assign(socket, :error_message, message)}
              end
            end
        end
    end
  end

  @impl true
  def handle_event("reset-game", _params, socket) do
    # Create a new empty board using the Board module
    empty_board = Game.create_empty_board(@board_size)

    players = socket.assigns.players || [socket.assigns.current_player.name]
    next_turn = List.first(players) || socket.assigns.current_player.name

    # Broadcast reset so all subscribers clear their state
    PubSub.broadcast(
      Wordgo.PubSub,
      socket.assigns.topic,
      {:reset, %{board: empty_board, next_turn: next_turn}}
    )

    current_player = socket.assigns.current_player

    word_groups = Game.get_player_groups(empty_board, current_player.name)
    group_scores = Game.get_player_groups_with_scores(empty_board, current_player.name)

    socket =
      socket
      |> assign(:board, empty_board)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:word_groups, word_groups)
      |> assign(:group_scores, group_scores)
      |> assign(:current_scope, "game")
      |> assign(:current_turn, next_turn)

    # Send an update message to refresh groups
    if connected?(socket) do
      send(self(), :update_groups)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update-word", %{"word" => word}, socket) do
    {:noreply, assign(socket, :current_word, word)}
  end

  @impl true
  def handle_event("set-ai-difficulty", %{"difficulty" => difficulty}, socket) do
    diff = String.downcase(to_string(difficulty))

    if diff in ["easy", "medium", "hard"] do
      PubSub.broadcast(Wordgo.PubSub, socket.assigns.topic, {:ai_difficulty, diff})
      {:noreply, assign(socket, :ai_difficulty, diff)}
    else
      {:noreply, socket}
    end
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

  # == Multiplayer coordination (PubSub) and AI turns ==

  defp next_player(players, current) do
    cond do
      players == [] ->
        current

      true ->
        idx = Enum.find_index(players, &(&1 == current)) || 0
        Enum.at(players, rem(idx + 1, length(players)))
    end
  end

  defp player_color(name) when is_binary(name) do
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

  defp build_player_colors(players) do
    Enum.reduce(players || [], %{}, fn name, acc ->
      Map.put(acc, name, player_color(name))
    end)
  end

  @impl true
  def handle_info(:request_state, socket) do
    if connected?(socket) do
      PubSub.broadcast(Wordgo.PubSub, socket.assigns.topic, {:request_state, self()})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:request_state, from}, socket) do
    state = %{
      board: socket.assigns.board,
      players: socket.assigns.players,
      current_turn: socket.assigns.current_turn,
      player_colors: socket.assigns.player_colors,
      ai_difficulty: socket.assigns.ai_difficulty
    }

    send(from, {:state, state})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state, state}, socket) do
    # Only accept the first state sync we receive
    if socket.assigns[:synced?] do
      {:noreply, socket}
    else
      players =
        state.players
        |> Enum.uniq()
        |> Kernel.++(Enum.reject([socket.assigns.current_player.name], &(&1 in state.players)))
        |> Enum.uniq()

      socket =
        socket
        |> assign(:board, state.board)
        |> assign(:players, players)
        |> assign(:current_turn, state.current_turn)
        |> assign(:player_colors, state.player_colors || build_player_colors(players))
        |> assign(:ai_difficulty, state.ai_difficulty || socket.assigns.ai_difficulty)
        |> assign(:synced?, true)

      send(self(), :update_groups)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:player_joined, player_name}, socket) do
    players = [player_name | socket.assigns.players || []] |> Enum.uniq()

    colors =
      (socket.assigns.player_colors || %{})
      |> Map.put_new(player_name, player_color(player_name))

    {:noreply, socket |> assign(:players, players) |> assign(:player_colors, colors)}
  end

  @impl true
  def handle_info({:ai_difficulty, diff}, socket) do
    diff = String.downcase(to_string(diff))

    if diff in ["easy", "medium", "hard"] do
      {:noreply, assign(socket, :ai_difficulty, diff)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:move, %{board: board, next_turn: next_turn}}, socket) do
    current_name = socket.assigns.current_player.name
    word_groups = Game.get_player_groups(board, current_name)
    group_scores = Game.get_player_groups_with_scores(board, current_name)

    socket =
      socket
      |> assign(:board, board)
      |> assign(:current_turn, next_turn)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:word_groups, word_groups)
      |> assign(:group_scores, group_scores)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:reset, %{board: board, next_turn: next_turn}}, socket) do
    current_name = socket.assigns.current_player.name
    word_groups = Game.get_player_groups(board, current_name)
    group_scores = Game.get_player_groups_with_scores(board, current_name)

    socket =
      socket
      |> assign(:board, board)
      |> assign(:current_turn, next_turn)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:word_groups, word_groups)
      |> assign(:group_scores, group_scores)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:ai_move, socket) do
    case AI.should_make_move?(socket.assigns) do
      {:ok, :skip_move} ->
        {:noreply, socket}

      {:ok, :should_move} ->
        case AI.execute_move(socket.assigns) do
          {:ok, updated_assigns} ->
            # Apply updated assigns to socket
            updated_socket =
              Enum.reduce(updated_assigns, socket, fn
                {:flash, _}, acc -> acc
                {key, value}, acc -> assign(acc, key, value)
              end)

            {:noreply, updated_socket}

          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end
end
