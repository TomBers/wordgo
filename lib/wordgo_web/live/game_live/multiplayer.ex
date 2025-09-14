defmodule WordgoWeb.GameLive.Multiplayer do
  @moduledoc """
  Handles multiplayer coordination logic for the GameLive view.

  This module encapsulates all PubSub message handling, including state
  synchronization, player updates, and broadcasting game events like moves
  and resets.
  """

  import Phoenix.Component

  alias Phoenix.PubSub
  alias Wordgo.Game
  alias WordgoWeb.GameLive.Helpers

  # == PubSub Message Handlers ==

  def handle_info(:request_state, socket) do
    if Phoenix.LiveView.connected?(socket) do
      PubSub.broadcast(Wordgo.PubSub, socket.assigns.topic, {:request_state, self()})
    end

    {:noreply, socket}
  end

  def handle_info({:request_state, from}, socket) do
    # A client should not provide state to itself. Only reply if the
    # requester is a different process.
    if from != self() do
      state = %{
        board: socket.assigns.board,
        players: socket.assigns.players,
        current_turn: socket.assigns.current_turn,
        ai_difficulty: socket.assigns.ai_difficulty
      }

      send(from, {:state, state})
    end

    {:noreply, socket}
  end

  def handle_info({:state, state}, socket) do
    # Only accept the first state sync we receive.
    if socket.assigns[:synced?] do
      {:noreply, socket}
    else
      # The received state is canonical. Add ourself to it and broadcast.
      current_player_name = socket.assigns.current_player.name
      players = [current_player_name | state.players] |> Enum.uniq()

      # Broadcast the complete list of players to ensure all clients are in sync.
      PubSub.broadcast(Wordgo.PubSub, socket.assigns.topic, {:update_players, players})

      socket =
        socket
        |> assign(:board, state.board)
        |> assign(:players, players)
        |> assign(:current_turn, state.current_turn)
        |> assign(:player_colors, Helpers.build_player_colors(players))
        |> assign(
          :ai_difficulty,
          state.ai_difficulty || socket.assigns.ai_difficulty
        )
        |> assign(:synced?, true)

      send(self(), :update_groups)
      {:noreply, socket}
    end
  end

  def handle_info({:player_joined, player_name}, socket) do
    # The new player receives their own join message and requests the canonical state.
    # We don't modify the player list here because the initial state is correct,
    # and the upcoming state sync will provide the full list of players.
    if player_name == socket.assigns.current_player.name do
      send(self(), :request_state)
    end

    # Existing players do nothing. They will get an `:update_players` message
    # shortly, which is the canonical source of truth for the player list.
    {:noreply, socket}
  end

  def handle_info({:update_players, players}, socket) do
    # This message is broadcast by a client that has just synced its state
    # to ensure all clients have a consistent view of the players.
    {:noreply,
     socket
     |> assign(:players, players)
     |> assign(:player_colors, Helpers.build_player_colors(players))}
  end

  def handle_info({:ai_difficulty, diff}, socket) do
    diff = String.downcase(to_string(diff))

    if diff in ["easy", "medium", "hard"] do
      {:noreply, assign(socket, :ai_difficulty, diff)}
    else
      {:noreply, socket}
    end
  end

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
end
