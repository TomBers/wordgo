defmodule Wordgo.Game.Setup do
  alias Wordgo.Game.{Board, Player, Piece}

  def run() do
    board = Board.new(3)
    player = Player.new("bob")
    player2 = Player.new("alice")
    player3 = Player.new("charlie")

    piece = Piece.new(1, 1, player, "Bill")
    piece2 = Piece.new(2, 2, player2, "Alice")
    piece3 = Piece.new(3, 3, player3, "Bob")
    piece4 = Piece.new(1, 2, player, "Bird")

    Board.place_piece(board, piece)
    |> Board.place_piece(piece2)
    |> Board.place_piece(piece3)
    |> Board.place_piece(piece4)
    |> Board.score()
  end
end
