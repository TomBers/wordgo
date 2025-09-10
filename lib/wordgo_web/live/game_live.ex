defmodule WordgoWeb.GameLive do
  use WordgoWeb, :live_view
  alias Wordgo.Game
  alias Phoenix.PubSub
  alias Wordgo.WordToVec.Vocabulary
  require Logger

  # Define the initial state for the game
  @board_size 6

  # Fixed palette for player colors (use Tailwind classes)
  @player_palette [
    "bg-red-300",
    "bg-green-300",
    "bg-blue-300",
    "bg-purple-300",
    "bg-pink-300",
    "bg-indigo-300",
    "bg-teal-300",
    "bg-orange-300",
    "bg-amber-300",
    "bg-lime-300"
  ]

  @impl true
  def mount(params, _session, socket) do
    game_id = params["game_id"] || "lobby"

    player_name =
      case params["player"] do
        nil -> "Player-#{:erlang.unique_integer([:positive])}"
        "" -> "Player-#{:erlang.unique_integer([:positive])}"
        name -> name
      end

    ai_enabled = params["ai"] == "true"
    ai_difficulty = params["ai_difficulty"] || "medium"
    topic = "game:" <> game_id

    # Create an empty board using the Board module
    empty_board = Game.create_empty_board(@board_size)

    # Initialize the current player
    current_player = Game.create_player(player_name, player_name)

    # Initialize player color map (deterministic by name)
    player_colors =
      %{}
      |> Map.put(current_player.name, player_color(current_player.name))

    player_colors =
      if ai_enabled do
        Map.put(player_colors, "AI", player_color("AI"))
      else
        player_colors
      end

    # Initialize with empty board and player
    socket =
      socket
      |> assign(:board, empty_board)
      |> assign(:board_size, @board_size)
      |> assign(:current_player, current_player)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:word_groups, [])
      |> assign(:group_scores, [])
      # Add current_scope for the layout
      |> assign(:current_scope, "game")
      |> assign(:game_id, game_id)
      |> assign(:topic, topic)
      |> assign(:players, [current_player.name])
      |> assign(:player_colors, player_colors)
      |> assign(:current_turn, current_player.name)
      |> assign(:ai_enabled, ai_enabled)
      |> assign(:ai_difficulty, ai_difficulty)
      |> assign(:synced?, false)

    if connected?(socket) do
      PubSub.subscribe(Wordgo.PubSub, topic)

      # Announce this player and optional AI
      PubSub.broadcast(Wordgo.PubSub, topic, {:player_joined, current_player.name})

      if ai_enabled do
        PubSub.broadcast(Wordgo.PubSub, topic, {:player_joined, "AI"})
      end

      # Ask other subscribers for the current state (if any)
      send(self(), :request_state)
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
    idx = :erlang.phash2(name, length(@player_palette))
    Enum.at(@player_palette, idx)
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
    cond do
      socket.assigns[:ai_enabled] != true ->
        {:noreply, socket}

      socket.assigns.current_turn != "AI" ->
        {:noreply, socket}

      true ->
        board = socket.assigns.board
        size = socket.assigns.board_size
        players = socket.assigns.players || ["AI"]
        ai_difficulty = socket.assigns[:ai_difficulty] || "medium"

        # Difficulty parameters: target similarity for word choice and weights for blocking/growth
        {target_sim, block_w, grow_w} =
          case String.downcase(to_string(ai_difficulty)) do
            "easy" -> {0.3, 1, 1}
            "hard" -> {0.85, 3, 1}
            # medium
            _ -> {0.6, 2, 1}
          end

        # Occupied and empty coords
        occupied =
          board.pieces
          |> Enum.map(&{&1.x, &1.y})
          |> MapSet.new()

        all_coords = for y <- 0..(size - 1), x <- 0..(size - 1), do: {x, y}
        empty = Enum.reject(all_coords, fn coord -> MapSet.member?(occupied, coord) end)

        if empty == [] do
          {:noreply, socket}
        else
          # Determine target human to block: next after AI, or first non-AI
          target_opponent =
            case next_player(players, "AI") do
              "AI" -> Enum.find(players, fn n -> n != "AI" end)
              other -> other
            end

          neighbors = fn {x, y} ->
            [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}]
            |> Enum.filter(fn {nx, ny} -> nx >= 0 and ny >= 0 and nx < size and ny < size end)
          end

          empty_set = MapSet.new(empty)

          ai_piece_coords =
            board.pieces
            |> Enum.filter(&(&1.player == "AI"))
            |> Enum.map(&{&1.x, &1.y})
            |> MapSet.new()

          frontier_coords =
            if target_opponent do
              groups = Game.get_player_groups(board, target_opponent)

              largest =
                case groups do
                  [] -> []
                  _ -> Enum.max_by(groups, &length/1, fn -> [] end)
                end

              largest
              |> Enum.flat_map(fn p -> neighbors.({p.x, p.y}) end)
              |> Enum.filter(&MapSet.member?(empty_set, &1))
              |> Enum.uniq()
              |> Enum.map(fn coord ->
                block_adj =
                  neighbors.(coord)
                  |> Enum.count(fn c ->
                    Enum.any?(largest, fn p -> {p.x, p.y} == c end)
                  end)

                grow_adj =
                  neighbors.(coord)
                  |> Enum.count(fn c -> MapSet.member?(ai_piece_coords, c) end)

                # 2-step lookahead:
                # - Opponent potential after this move: best adjacent-to-group empty cell remaining
                empty_after = MapSet.delete(empty_set, coord)

                opp_next_best =
                  neighbors
                  |> then(fn nb ->
                    largest
                    |> Enum.flat_map(fn p -> nb.({p.x, p.y}) end)
                    |> Enum.filter(&MapSet.member?(empty_after, &1))
                    |> Enum.map(fn c2 ->
                      nb.(c2)
                      |> Enum.count(fn c3 ->
                        Enum.any?(largest, fn p -> {p.x, p.y} == c3 end)
                      end)
                    end)
                    |> Enum.max(fn -> 0 end)
                  end)

                # - AI future growth from this cell: how many empty neighbors remain
                ai_future =
                  neighbors.(coord)
                  |> Enum.count(&MapSet.member?(empty_after, &1))

                final_score =
                  block_w * block_adj + grow_w * grow_adj + div(grow_w * ai_future, 2) -
                    opp_next_best

                {coord, final_score, block_adj, grow_adj}
              end)
              |> Enum.sort_by(
                fn {_c, score, block_adj, grow_adj} -> {score, block_adj, grow_adj} end,
                :desc
              )
            else
              []
            end

          chosen_coord =
            case frontier_coords do
              [{coord, _score, _b, _g} | _] ->
                coord

              _ ->
                # If no frontier to block, try to grow near AI pieces, else random
                grow_candidates =
                  empty
                  |> Enum.map(fn coord ->
                    adj =
                      neighbors.(coord)
                      |> Enum.count(&MapSet.member?(ai_piece_coords, &1))

                    {coord, adj}
                  end)
                  |> Enum.sort_by(fn {_c, adj} -> adj end, :desc)

                case grow_candidates do
                  [{coord, _} | _] -> coord
                  _ -> Enum.random(empty)
                end
            end

          {x, y} = chosen_coord

          # Choose a word with vocabulary similarity based on difficulty
          ai_words = Game.get_player_words(board, "AI")

          word =
            case ai_words do
              [] ->
                # First move: random vocabulary word
                vocab = Vocabulary.get_vocabulary()
                Enum.random(vocab)

              _ ->
                # Choose base word from the AI group nearest to the chosen coordinate, fallback to any AI word
                ai_groups = Game.get_player_groups(board, "AI")

                {nearest_group, _dist} =
                  ai_groups
                  |> Enum.map(fn grp ->
                    min_dist =
                      grp
                      |> Enum.map(fn p -> abs(p.x - x) + abs(p.y - y) end)
                      |> Enum.min(fn -> 999_999 end)

                    {grp, min_dist}
                  end)
                  |> Enum.min_by(fn {_g, d} -> d end, fn -> {[], 999_999} end)

                base_candidates =
                  case nearest_group do
                    [] -> ai_words
                    grp -> Enum.map(grp, & &1.word)
                  end

                base = Enum.random(base_candidates)

                case Vocabulary.best_match_for_desired_similarity(base, target_sim) do
                  {w, _sim} ->
                    w

                  _ ->
                    vocab = Vocabulary.get_vocabulary()
                    Enum.random(vocab)
                end
            end

          case Game.place_word(board, {x, y}, word, "AI") do
            {:ok, updated_board} ->
              players2 = socket.assigns.players || ["AI"]
              next_turn = next_player(players2, "AI")

              PubSub.broadcast(
                Wordgo.PubSub,
                socket.assigns.topic,
                {:move, %{board: updated_board, next_turn: next_turn}}
              )

              # Update local UI too
              current_name = socket.assigns.current_player.name
              word_groups = Game.get_player_groups(updated_board, current_name)
              group_scores = Game.get_player_groups_with_scores(updated_board, current_name)

              socket =
                socket
                |> assign(:board, updated_board)
                |> assign(:current_turn, next_turn)
                |> assign(:selected_position, nil)
                |> assign(:current_word, "")
                |> assign(:error_message, nil)
                |> assign(:word_groups, word_groups)
                |> assign(:group_scores, group_scores)

              {:noreply, socket}

            {:error, _} ->
              {:noreply, socket}
          end
        end
    end
  end
end
