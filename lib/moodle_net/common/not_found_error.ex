# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Common.NotFoundError do
  @enforce_keys [:message, :code, :status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
    message: binary,
    code: binary,
    status: integer,
  }

  @doc "Create a new NotFoundError"
  @spec new() :: t
  def new() do
    %__MODULE__{
      message: "Not found",
      code: "not_found",
      status: 404,
    }
  end

end
