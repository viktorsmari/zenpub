# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2019 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Comments do
  alias MoodleNet.{Common, Meta}
  alias MoodleNet.Comments.{Comment, Thread}
  alias MoodleNet.Common.{Revision, NotFoundError}
  alias MoodleNet.Repo

  def fetch_thread(id), do: Repo.fetch(Thread, id)
  def fetch_comment(id), do: Repo.fetch(Comment, id)

  def create_thread(parent, creator, attrs) do
    Repo.transact_with fn ->
      parent = Meta.find!(parent.id)
      pointer = Meta.point_to!(Thread)
      Repo.insert(Thread.create_changeset(pointer, parent, creator, attrs))
    end
  end

  def update_thread(thread, attrs) do
    Repo.transact_with fn ->
      Repo.update(Thread.update_changeset(thread, attrs))
    end
  end

  def create_comment(thread, creator, attrs) when is_map(attrs) do
    Repo.transact_with(fn ->
      pointer = Meta.point_to!(Comment)
      Repo.insert(Comment.create_changeset(pointer, creator, thread, attrs))
    end)
  end

  def update_comment(%Comment{} = comment, attrs) do
    Repo.update(Comment.update_changeset(comment, attrs))
  end
end