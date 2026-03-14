defmodule Bookmoves.Openings.GameId do
  @moduledoc false

  @prefix "lichess:"

  @spec from_lichess_id(String.t()) :: integer()
  def from_lichess_id(lichess_id) when is_binary(lichess_id) do
    <<id::signed-big-integer-size(64), _rest::binary>> =
      :crypto.hash(:sha256, @prefix <> lichess_id)

    id
  end
end
