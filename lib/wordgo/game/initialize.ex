defmodule Wordgo.Game.Initialize do
  @moduledoc """
  Handles game initialization logic for new game sessions.
  Extracted from GameLive to provide better separation of concerns and testability.
  """

  alias Wordgo.Game
  alias Phoenix.PubSub

  @doc """
  Initializes a complete game session with all necessary assigns.

  ## Parameters
  - params: Map containing game parameters (game_id, player, ai, ai_difficulty)
  - board_size: Integer board size

  ## Returns
  Map of assigns ready to be applied to a LiveView socket
  """
  def initialize_game_session(params) do
    game_id = params["game_id"] || "lobby"
    board_size = String.to_integer(params["board_size"] || "6")
    bonus = String.to_integer(params["bonus"] || "0")
    player_name = normalize_player_name(params["player"])
    ai_config = extract_ai_config(params)

    # Hybrid win conditions: score limit and optional time limit (nil means unlimited)
    score_limit = String.to_integer(params["score_limit"] || "100")

    game_duration_ms =
      case params["game_duration_ms"] do
        nil ->
          nil

        "" ->
          nil

        val ->
          case Integer.parse(val) do
            {ms, _} when ms > 0 -> ms
            _ -> nil
          end
      end

    game_started_at =
      if game_duration_ms do
        DateTime.utc_now()
      else
        nil
      end

    game_end_at =
      if game_duration_ms && game_started_at do
        DateTime.add(game_started_at, game_duration_ms, :millisecond)
      else
        nil
      end

    # Create core game components
    empty_board = Game.create_empty_board(board_size, bonus)
    current_player = Game.create_player(player_name, player_name)
    player_colors = build_player_colors(current_player, ai_config.enabled)

    players =
      if ai_config.enabled do
        [current_player.name, "AI"]
      else
        [current_player.name]
      end

    # Build complete assigns map
    %{
      board: empty_board,
      board_size: board_size,
      current_player: current_player,
      selected_position: nil,
      current_word: "",
      error_message: nil,
      word_groups: [],
      group_scores: [],
      current_scope: "game",
      game_id: game_id,
      topic: "game:" <> game_id,
      players: players,
      player_colors: player_colors,
      current_turn: current_player.name,
      ai_enabled: ai_config.enabled,
      ai_difficulty: ai_config.difficulty,
      # Hybrid win condition fields
      score_limit: score_limit,
      game_duration_ms: game_duration_ms,
      game_started_at: game_started_at,
      game_end_at: game_end_at,
      game_over?: false,
      winner: nil,
      final_scores: nil,
      synced?: false
    }
  end

  @doc """
  Handles post-mount initialization for connected sockets.
  This includes PubSub subscriptions and player announcements.

  ## Parameters
  - assigns: Map of socket assigns
  - pubsub_module: PubSub module (default: Wordgo.PubSub)

  ## Returns
  List of messages to send to self()
  """
  def handle_connected_initialization(assigns, pubsub_module \\ Wordgo.PubSub) do
    topic = assigns.topic
    # current_player_name = assigns.current_player.name
    # ai_enabled = assigns.ai_enabled

    # Subscribe to game topic
    PubSub.subscribe(pubsub_module, topic)

    # Timer scheduling is handled by the LiveView mount; no scheduling here

    # Return messages to send
    [:request_state, :update_groups]
  end

  @doc """
  Normalizes player name from params, generating unique name if needed.
  """
  def normalize_player_name(player_param) do
    case player_param do
      nil -> generate_player_name()
      "" -> generate_player_name()
      name -> name
    end
  end

  @doc """
  Extracts AI configuration from params.

  ## Returns
  Map with :enabled and :difficulty keys
  """
  def extract_ai_config(params) do
    %{
      enabled: params["ai"] == "true",
      difficulty: params["ai_difficulty"] || "medium"
    }
  end

  @doc """
  Builds player color mapping for all players in the game.
  """
  def build_player_colors(current_player, ai_enabled) do
    colors =
      %{}
      |> Map.put(current_player.name, player_color(current_player.name))

    if ai_enabled do
      Map.put(colors, "AI", player_color("AI"))
    else
      colors
    end
  end

  # Private functions

  defp generate_player_name do
    "Player-#{:erlang.unique_integer([:positive])}"
  end

  # Deterministic color assignment based on player name
  defp player_color(name) do
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
end
