defmodule WordgoWeb.GameLive do
  use WordgoWeb, :live_view

  alias Wordgo.Game
  alias Wordgo.Game.Initialize
  alias Wordgo.Game.AI
  alias Wordgo.Game.Board
  alias Phoenix.PubSub
  alias WordgoWeb.GameLive.Multiplayer
  alias WordgoWeb.GameLive.Helpers

  require Logger

  # == Lifecycle ==

  @impl true
  def mount(params, _session, socket) do
    game_assigns = Initialize.initialize_game_session(params)

    socket = assign(socket, Map.drop(game_assigns, [:flash]))
    socket = assign(socket, :show_place_modal, false)

    # Hybrid win condition defaults if not already set
    socket =
      socket
      |> assign_new(:score_limit, fn -> 100 end)
      |> assign_new(:game_duration_ms, fn -> nil end)
      |> assign_new(:game_started_at, fn -> nil end)
      |> assign_new(:game_end_at, fn -> nil end)
      |> assign_new(:game_over?, fn -> false end)
      |> assign_new(:winner, fn -> nil end)
      |> assign_new(:final_scores, fn -> nil end)

    if connected?(socket) do
      messages_to_send = Initialize.handle_connected_initialization(socket.assigns)
      Enum.each(messages_to_send, &send(self(), &1))

      # Schedule time-up event only if a duration is configured
      if match?(%DateTime{}, socket.assigns[:game_end_at]) do
        remaining_ms =
          max(DateTime.diff(socket.assigns.game_end_at, DateTime.utc_now(), :millisecond), 0)

        Process.send_after(self(), :time_up, remaining_ms)
      end
    end

    {:ok, socket}
  end

  # == Event Handlers ==

  @impl true
  def handle_event("select-position", %{"x" => x, "y" => y}, socket) do
    x = String.to_integer(x)
    y = String.to_integer(y)
    board = socket.assigns.board

    if socket.assigns[:game_over?] do
      {:noreply, assign(socket, :error_message, "Game over. Reset to play again.")}
    else
      if Enum.any?(board.pieces, &(&1.x == x && &1.y == y)) do
        {:noreply, assign(socket, :error_message, "That position is already occupied")}
      else
        {:noreply,
         socket
         |> assign(:selected_position, {x, y})
         |> assign(:show_place_modal, true)
         |> assign(:error_message, nil)}
      end
    end
  end

  @impl true
  def handle_event("place-word", %{"word" => word}, socket) do
    word = String.trim(word)
    current_name = socket.assigns.current_player.name

    cond do
      socket.assigns[:game_over?] ->
        {:noreply, assign(socket, :error_message, "Game over. Reset to play again.")}

      socket.assigns.current_turn && socket.assigns.current_turn != current_name ->
        {:noreply, assign(socket, :error_message, "It's not your turn")}

      word == "" ->
        {:noreply, assign(socket, :error_message, "Please enter a word")}

      String.length(word) > 20 ->
        {:noreply, assign(socket, :error_message, "Word is too long (maximum 20 characters)")}

      true ->
        case socket.assigns.selected_position do
          nil ->
            {:noreply,
             assign(socket, :error_message, "Please select a position on the board first")}

          {x, y} ->
            existing_words = Enum.map(socket.assigns.board.pieces, &String.downcase(&1.word))

            if String.downcase(word) in existing_words do
              {:noreply, assign(socket, :error_message, "That word is already on the board")}
            else
              case Game.place_word(socket.assigns.board, {x, y}, word, current_name) do
                {:ok, updated_board} ->
                  players = socket.assigns.players || [current_name]
                  next_turn = Helpers.next_player(players, current_name)

                  PubSub.broadcast(
                    Wordgo.PubSub,
                    socket.assigns.topic,
                    {:move, %{board: updated_board, next_turn: next_turn}}
                  )

                  send(self(), :update_groups)

                  socket =
                    socket
                    |> assign(:board, updated_board)
                    |> assign(:selected_position, nil)
                    |> assign(:current_word, "")
                    |> assign(:error_message, nil)
                    |> assign(:current_turn, next_turn)
                    |> assign(:show_place_modal, false)

                  # Check score limit win condition
                  socket =
                    maybe_finalize_by_score(socket)

                  if socket.assigns[:ai_enabled] && next_turn == "AI" &&
                       not socket.assigns[:game_over?] do
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
    empty_board = Game.create_empty_board(socket.assigns.board_size)
    players = socket.assigns.players || [socket.assigns.current_player.name]
    next_turn = List.first(players)

    PubSub.broadcast(
      Wordgo.PubSub,
      socket.assigns.topic,
      {:reset, %{board: empty_board, next_turn: next_turn}}
    )

    send(self(), :update_groups)

    # Reset state and timer
    duration = socket.assigns[:game_duration_ms]

    {started_at, end_at} =
      if is_integer(duration) and duration > 0 do
        now = DateTime.utc_now()
        {now, DateTime.add(now, duration, :millisecond)}
      else
        {nil, nil}
      end

    socket =
      socket
      |> assign(:board, empty_board)
      |> assign(:selected_position, nil)
      |> assign(:current_word, "")
      |> assign(:error_message, nil)
      |> assign(:current_turn, next_turn)
      |> assign(:show_place_modal, false)
      |> assign(:game_over?, false)
      |> assign(:winner, nil)
      |> assign(:final_scores, nil)
      |> assign(:game_started_at, started_at)
      |> assign(:game_end_at, end_at)

    if match?(%DateTime{}, end_at) do
      Process.send_after(self(), :time_up, duration)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update-word", %{"word" => word}, socket) do
    {:noreply, assign(socket, :current_word, word)}
  end

  def handle_event("close-place-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_place_modal, false)
     |> assign(:error_message, nil)
     |> assign(:current_word, "")
     |> assign(:selected_position, nil)}
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

  # == Local Message Handlers ==

  @impl true
  def handle_info(:update_groups, socket) do
    board = socket.assigns.board
    player_name = socket.assigns.current_player.name

    word_groups = Game.get_player_groups(board, player_name)
    group_scores = Game.get_player_groups_with_scores(board, player_name)

    socket =
      socket
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
            updated_socket = assign(socket, Map.drop(updated_assigns, [:flash]))

            # Broadcast the AI's move to all clients
            PubSub.broadcast(
              Wordgo.PubSub,
              socket.assigns.topic,
              {:move,
               %{
                 board: updated_socket.assigns.board,
                 next_turn: updated_socket.assigns.current_turn
               }}
            )

            updated_socket = maybe_finalize_by_score(updated_socket)

            {:noreply, updated_socket}

          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end

  # == Hybrid Win Conditions ==

  @impl true
  def handle_info(:time_up, socket) do
    # Ignore time_up when timer is disabled/unlimited
    if not match?(%DateTime{}, socket.assigns[:game_end_at]) do
      {:noreply, socket}
    else
      if socket.assigns[:game_over?] do
        {:noreply, socket}
      else
        board = socket.assigns.board
        final_scores = Board.score(board)

        winner =
          case final_scores do
            [] ->
              nil

            scores ->
              max_score = Enum.max_by(scores, fn {_p, s} -> s end) |> elem(1)
              top = Enum.filter(scores, fn {_p, s} -> s == max_score end)

              case top do
                [{p, _}] -> p
                _ -> nil
              end
          end

        PubSub.broadcast(
          Wordgo.PubSub,
          socket.assigns.topic,
          {:game_over, %{reason: :time_up, winner: winner, final_scores: final_scores}}
        )

        {:noreply,
         socket
         |> assign(:game_over?, true)
         |> assign(:winner, winner)
         |> assign(:final_scores, final_scores)}
      end
    end
  end

  @impl true
  def handle_info(
        {:game_over, %{reason: _reason, winner: winner, final_scores: final_scores}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:game_over?, true)
     |> assign(:winner, winner)
     |> assign(:final_scores, final_scores)}
  end

  # == Multiplayer Message Handlers (Delegated) ==
  @impl true
  def handle_info(message, socket) do
    # Delegate all other messages to the Multiplayer module
    Multiplayer.handle_info(message, socket)
  end

  @doc """
  Rounds a score to two decimal places.
  """
  def round_score(score) when is_number(score) do
    if score > 0 do
      Float.round(score, 2)
    else
      0
    end
  end

  def round_score(score) do
    score
  end

  # == Helpers for win conditions ==
  defp maybe_finalize_by_score(socket) do
    limit = socket.assigns[:score_limit] || 100
    board = socket.assigns.board

    final_scores = Board.score(board)
    {_, max_score} = Enum.max_by(final_scores, fn {_p, s} -> s end, fn -> {nil, 0} end)

    if max_score >= limit do
      winner =
        case final_scores do
          [] ->
            nil

          scores ->
            top = Enum.filter(scores, fn {_p, s} -> s == max_score end)

            case top do
              [{p, _}] -> p
              _ -> nil
            end
        end

      PubSub.broadcast(
        Wordgo.PubSub,
        socket.assigns.topic,
        {:game_over, %{reason: :score_limit, winner: winner, final_scores: final_scores}}
      )

      socket
      |> assign(:game_over?, true)
      |> assign(:winner, winner)
      |> assign(:final_scores, final_scores)
    else
      socket
    end
  end

  def get_bonus(board, x, y) do
    Enum.find(board.bonus, %{symbol: "+"}, fn p -> p.x == x && p.y == y end)
  end
end
