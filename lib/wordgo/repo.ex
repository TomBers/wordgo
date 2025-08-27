defmodule Wordgo.Repo do
  use Ecto.Repo,
    otp_app: :wordgo,
    adapter: Ecto.Adapters.Postgres
end
