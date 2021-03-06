defmodule Measurement.Unit do

  use MoodleNet.Common.Schema
  
  import MoodleNet.Common.Changeset, only: [change_public: 1, change_disabled: 1]

  alias Ecto.Changeset
  alias MoodleNet.Actors.Actor
  alias MoodleNet.Meta.Pointer
  alias MoodleNet.Users.User
  alias Measurement.Unit

  @type t :: %__MODULE__{}

  table_schema "measurement_unit" do
    field :label, :string
    field :symbol, :string

    field(:is_public, :boolean, virtual: true)
    field(:published_at, :utc_datetime_usec)
    field(:is_disabled, :boolean, virtual: true, default: false)
    field(:disabled_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)

    belongs_to(:creator, User)
    belongs_to(:context, Pointer)

    timestamps()
  end

  @required ~w(label symbol)a
  @cast @required ++ ~w(is_disabled is_public)a

  def create_changeset(
        %User{} = creator,
        attrs
      ) do
    %Measurement.Unit{}
    |> Changeset.cast(attrs, @cast)
    |> Changeset.validate_required(@required)
    |> Changeset.change(
      creator_id: creator.id,
      is_public: true
    )
    |> common_changeset()
  end

  def create_changeset(
      %User{} = creator,
      %{id: _} = context,
      attrs
    ) do
  %Measurement.Unit{}
  |> Changeset.cast(attrs, @cast)
  |> Changeset.validate_required(@required)
  |> Changeset.change(
    creator_id: creator.id,
    context_id: context.id,
    is_public: true
  )
  |> common_changeset()
  end

  def update_changeset(%Measurement.Unit{} = unit, attrs) do
    unit
    |> Changeset.cast(attrs, @cast)
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    |> change_public()
    |> change_disabled()
  end

end
