defmodule Bookmoves.Repo do
  use Ecto.Repo,
    otp_app: :bookmoves,
    adapter: Ecto.Adapters.SQLite3
end
