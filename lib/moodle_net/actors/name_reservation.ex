# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# Contains code from Pleroma <https://pleroma.social/> and CommonsPub <https://commonspub.org/>
defmodule MoodleNet.Actors.NameReservation do

  use Ecto.Schema
  alias Ecto.Changeset
  alias MoodleNet.Actors.NameReservation

  @primary_key {:id, Cloak.Ecto.SHA256, autogenerate: false}
  schema "actor_name_reservation" do
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  def changeset(name) when is_binary(name) do
    Changeset.change(%NameReservation{}, id: name)
  end

end
