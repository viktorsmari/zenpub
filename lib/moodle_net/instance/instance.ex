# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Instance do
  @moduledoc "A proxy for everything happening on this instance"

  def hostname(config \\ config()) do
    Keyword.fetch!(config, :hostname)
  end

  def description(config \\ config()) do
    Keyword.fetch!(config, :description)
  end

  def base_url(), do: Application.fetch_env!(:moodle_net, :base_url)

  @doc false
  def default_outbox_query_contexts(config \\ config()) do
    Keyword.fetch!(config, :default_outbox_query_contexts)
  end

  defp config(), do: Application.fetch_env!(:moodle_net, __MODULE__)

end

