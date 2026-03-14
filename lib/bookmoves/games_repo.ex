defmodule Bookmoves.GamesRepo do
  use Ecto.Repo,
    otp_app: :bookmoves,
    priv: "priv/games_repo",
    adapter: Ecto.Adapters.Postgres
end
