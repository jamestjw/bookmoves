defmodule Bookmoves.Repertoire.Repertoire do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          color_side: String.t() | nil,
          user_id: pos_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type persisted_t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          color_side: String.t(),
          user_id: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type attrs :: %{
          required(:name) => String.t(),
          required(:color_side) => String.t()
        }

  schema "repertoires" do
    field :name, :string
    field :color_side, :string

    belongs_to :user, Bookmoves.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(repertoire, attrs) do
    repertoire
    |> cast(attrs, [:name, :color_side])
    |> validate_required([:name, :color_side])
    |> validate_inclusion(:color_side, ["white", "black"])
    |> validate_length(:name, min: 1, max: 80)
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :name], name: :repertoires_user_name_index)
  end
end
