# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Follows.FollowerCount do
  use MoodleNet.Common.Schema
  alias MoodleNet.Meta.Pointer

  view_schema "mn_follower_count" do
    belongs_to(:context, Pointer, primary_key: true)
    field(:count, :integer)
  end
end
