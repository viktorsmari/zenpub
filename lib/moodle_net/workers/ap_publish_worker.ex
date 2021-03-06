# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Workers.APPublishWorker do
  use ActivityPub.Workers.WorkerHelper, queue: "mn_ap_publish", max_attempts: 1

  require Logger

  alias MoodleNet.ActivityPub.Publisher
  alias MoodleNet.Blocks.Block
  alias MoodleNet.Flags.Flag
  alias MoodleNet.Follows.Follow
  alias MoodleNet.Likes.Like
  alias MoodleNet.Collections.Collection
  alias MoodleNet.Communities.Community
  alias MoodleNet.Meta.Pointers
  alias MoodleNet.Resources.Resource
  alias MoodleNet.Threads.Comment
  alias MoodleNet.Users.User

  @moduledoc """
  Module for publishing ActivityPub activities.

  Intended entry point for this module is the `__MODULE__.enqueue/2` function
  provided by `ActivityPub.Workers.WorkerHelper` module.

  Note that the `"context_id"` argument refers to the ID of the object being
  federated and not to the ID of the object context, if present.
  """

  @spec batch_enqueue(String.t(), list(String.t())) :: list(Oban.Job.t())
  @doc """
  Enqueues a number of jobs provided a verb and a list of string IDs.
  """
  def batch_enqueue(verb, ids) do
    Enum.map(ids, fn id -> enqueue(verb, %{"context_id" => id}) end)
  end

  @impl Worker
  def perform(%{"context_id" => context_id, "op" => "delete"}, _job) do
    object =
      with {:error, _e} <- MoodleNet.Users.one(join: :actor, preload: :actor, id: context_id),
           {:error, _e} <- MoodleNet.Communities.one(join: :actor, preload: :actor, id: context_id),
           {:error, _e} <- MoodleNet.Collections.one(join: :actor, preload: :actor, id: context_id) do
        {:error, "not found"}
      end

      case object do
        {:ok, object} -> only_local(object, &publish/2, "delete")
        _ ->
          Pointers.one!(id: context_id)
          |> Pointers.follow!()
          |> only_local(&publish/2, "delete")
      end
  end

  def perform(%{"context_id" => context_id, "op" => verb}, _job) do
    Pointers.one!(id: context_id)
    |> Pointers.follow!()
    |> only_local(&publish/2, verb)
  end

  defp publish(%Collection{} = collection, "create"), do: Publisher.create_collection(collection)

  defp publish(%Comment{} = comment, "create") do
    Publisher.comment(comment)
  end

  defp publish(%Resource{} = resource, "create") do
    Publisher.create_resource(resource)
  end

  defp publish(%Community{} = community, "create") do
    Publisher.create_community(community)
  end

  defp publish(%Follow{} = follow, "create") do
    Publisher.follow(follow)
  end

  defp publish(%Follow{} = follow, "delete") do
    Publisher.unfollow(follow)
  end

  defp publish(%Flag{} = flag, "create") do
    Publisher.flag(flag)
  end

  defp publish(%Block{} = block, "create") do
    Publisher.block(block)
  end

  defp publish(%Block{} = block, "delete") do
    Publisher.unblock(block)
  end

  defp publish(%Like{} = like, "create") do
    Publisher.like(like)
  end

  defp publish(%Like{} = like, "delete") do
    Publisher.unlike(like)
  end

  defp publish(%{__struct__: type} = actor, "update")
       when type in [User, Community, Collection] do
    Publisher.update_actor(actor)
  end

  defp publish(%User{} = user, "delete") do
    Publisher.delete_user(user)
  end

  defp publish(%{__struct__: type} = actor, "delete")
       when type in [Community, Collection] do
    Publisher.delete_comm_or_coll(actor)
  end

  defp publish(%{__struct__: type} = object, "delete") when type in [Comment, Resource] do
    Publisher.delete_comment_or_resource(object)
  end

  defp publish(context, verb) do
    Logger.warn(
      "Unsupported action for AP publisher: #{context.id}, #{verb} #{context.__struct__}"
    )

    :ignored
  end

  defp only_local(%Resource{collection_id: collection_id} = context, commit_fn, verb) do
    with {:ok, collection} <- MoodleNet.Collections.one(id: collection_id),
         {:ok, actor} <- MoodleNet.Actors.one(id: collection.actor_id),
         true <- is_nil(actor.peer_id) do
      commit_fn.(context, verb)
    else
      _ ->
        :ignored
    end
  end

  defp only_local(%{is_local: true} = context, commit_fn, verb) do
    commit_fn.(context, verb)
  end

  defp only_local(%{actor: %{peer_id: nil}} = context, commit_fn, verb) do
    commit_fn.(context, verb)
  end

  defp only_local(_, _, _), do: :ignored
end
