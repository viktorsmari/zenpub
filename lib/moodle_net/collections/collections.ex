# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2019 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Collections do
  alias MoodleNet.{Activities, Actors, Common, Feeds, Meta, Users, Repo}
  alias MoodleNet.Actors.Actor
  alias MoodleNet.Common.Query
  alias MoodleNet.Collections.{Collection, Outbox}
  alias MoodleNet.Communities.Community
  alias MoodleNet.Users.User
  alias Ecto.Association.NotLoaded
  import Ecto.Query

  def count_for_list(), do: Repo.one(count_for_list_q())

  @spec list() :: [Collection.t()]
  def list() do
    Enum.map(Repo.all(list_q()), fn {collection, actor, count} ->
      %Collection{collection | actor: actor, follower_count: count}
    end)
  end

  defp list_q() do
    Collection
    |> Query.only_public()
    |> Query.only_undeleted()
    |> Query.order_by_recently_updated()
    |> only_from_undeleted_communities()
    |> follower_count_q()
  end

  defp only_from_undeleted_communities(query) do
    from(q in query,
      join: c in assoc(q, :community),
      on: q.community_id == c.id,
      where: not is_nil(c.published_at),
      where: is_nil(c.deleted_at)
    )
  end

  defp follower_count_q(query) do
    from(q in query,
      join: a in Actor,
      on: a.id == q.actor_id,
      left_join: fc in assoc(q, :follower_count),
      select: {q, a, fc},
      limit: 100,
      order_by: [desc: fc.count, desc: a.id]
    )
  end

  defp count_for_list_q() do
    Collection
    |> Query.only_public()
    |> Query.only_undeleted()
    |> only_from_undeleted_communities()
    |> Query.count()
  end

  def count_for_list_in_community(%Community{id: id}) do
    Repo.one(count_for_list_in_community_q(id))
  end

  def list_in_community(%Community{id: id}) do
    Repo.all(list_in_community_q(id))
  end

  defp list_in_community_q(id) do
    from(coll in Collection,
      join: comm in Community,
      on: coll.community_id == comm.id,
      join: a in Actor,
      on: coll.actor_id == a.id,
      where: comm.id == ^id,
      where: not is_nil(coll.published_at),
      where: is_nil(coll.deleted_at),
      where: not is_nil(comm.published_at),
      where: is_nil(comm.deleted_at),
      select: coll,
      preload: [actor: a]
    )
  end

  defp count_for_list_in_community_q(id) do
    from(coll in Collection,
      join: comm in Community,
      on: coll.community_id == comm.id,
      where: comm.id == ^id,
      where: not is_nil(coll.published_at),
      where: is_nil(coll.deleted_at),
      where: not is_nil(comm.published_at),
      where: is_nil(comm.deleted_at),
      select: count(coll)
    )
  end

  def fetch(id) when is_binary(id) do
    with {:ok, coll} <- Repo.single(fetch_q(id)) do
      {:ok, preload(coll)}
    end
  end

  defp fetch_q(id) do
    from(coll in Collection,
      join: comm in assoc(coll, :community),
      join: a in assoc(coll, :actor),
      where: coll.id == ^id,
      where: not is_nil(coll.published_at),
      where: is_nil(coll.deleted_at),
      where: not is_nil(comm.published_at),
      where: is_nil(comm.deleted_at),
      select: coll,
      preload: [actor: a]
    )
  end

  defp fetch_by_username_q(username) do
    from(coll in Collection,
      join: comm in assoc(coll, :community),
      join: a in assoc(coll, :actor),
      on: coll.actor_id == a.id,
      where: a.preferred_username == ^username,
      where: not is_nil(coll.published_at),
      where: is_nil(coll.deleted_at),
      where: not is_nil(comm.published_at),
      where: is_nil(comm.deleted_at),
      select: coll,
      preload: [actor: a]
    )
  end


  def fetch_by_username(username) when is_binary(username) do
    with {:ok, coll} <- Repo.single(fetch_by_username_q(username)) do
      {:ok, preload(coll)}
    end
  end

  @spec create(User.t(), Community.t(), attrs :: map) :: {:ok, Collection.t()} | {:error, Changeset.t()}
  def create(%User{} = creator, %Community{} = community, attrs) when is_map(attrs) do
    Repo.transact_with(fn ->
      with {:ok, actor} <- Actors.create(attrs),
           {:ok, coll_attrs} <- create_boxes(actor, attrs),
           {:ok, coll} <- insert_collection(creator, community, actor, coll_attrs),
           act_attrs = %{verb: "created", is_local: true},
           {:ok, activity} <- Activities.create(creator, coll, act_attrs),
           :ok <- publish(creator, community, coll, activity, :created) do
        {:ok, coll}
      end
    end)
  end

  defp create_boxes(%{peer_id: nil}, attrs), do: create_local_boxes(attrs)
  defp create_boxes(%{peer_id: _}, attrs), do: create_remote_boxes(attrs)

  defp create_local_boxes(attrs) do
    with {:ok, inbox} <- Feeds.create_feed(),
         {:ok, outbox} <- Feeds.create_feed() do
      extra = %{inbox_id: inbox.id, outbox_id: outbox.id}
      {:ok, Map.merge(attrs, extra)}
    end
  end

  defp create_remote_boxes(attrs) do
    with {:ok, outbox} <- Feeds.create_feed() do
      {:ok, Map.put(attrs, :outbox_id, outbox.id)}
    end
  end

  defp insert_collection(creator, community, actor, attrs) do
    cs = Collection.create_changeset(creator, community, actor, attrs)
    with {:ok, coll} <- Repo.insert(cs), do: {:ok, %{ coll | actor: actor }}
  end

  defp publish(creator, community, collection, activity, :created) do
    feeds = [community.outbox_id, creator.outbox_id, collection.outbox_id]
    with :ok <- Feeds.publish_to_feeds(feeds, activity) do
      ap_publish(collection.id, creator.id, collection.actor.peer_id)
    end
  end
  defp publish(collection, :updated) do
    ap_publish(collection.id, collection.creator_id, collection.actor.peer_id) # TODO: wrong if edited by admin
  end
  defp publish(collection, :deleted) do
    ap_publish(collection.id, collection.creator_id, collection.actor.peer_id) # TODO: wrong if edited by admin
  end

  defp ap_publish(context_id, user_id, nil) do
    MoodleNet.FeedPublisher.publish(%{
      "context_id" => context_id,
      "user_id" => user_id,
    })
  end
  defp ap_publish(_, _, _), do: :ok

  # TODO: take the user who is performing the update
  @spec update(%Collection{}, attrs :: map) :: {:ok, Collection.t()} | {:error, Changeset.t()}
  def update(%Collection{} = collection, attrs) do
    Repo.transact_with(fn ->
      collection = Repo.preload(collection, :community)
      community = collection.community
      with {:ok, collection} <- Repo.update(Collection.update_changeset(collection, attrs)),
           {:ok, actor} <- Actors.update(collection.actor, attrs),
           :ok <- publish(collection, :updated) do
        {:ok, %{ collection | actor: actor }}
      end
    end)
  end

  def soft_delete(%Collection{} = collection) do
    Repo.transact_with(fn ->
      with {:ok, collection} <- Common.soft_delete(collection),
           :ok <- publish(collection, :deleted) do
        {:ok, collection}
      end
    end)
  end

  def preload(collection, opts \\ [])

  def preload(%Collection{} = collection, opts) do
    Repo.preload(collection, :actor, opts)
  end

  def preload(collections, opts) when is_list(collections) do
    Repo.preload(collections, :actor, opts)
  end

  def fetch_creator(%Collection{creator_id: id, creator: %NotLoaded{}}), do: Users.fetch(id)
  def fetch_creator(%Collection{creator: creator}), do: {:ok, creator}

  def outbox(collection, opts \\ %{})
  def outbox(%Collection{outbox_id: outbox_id}=collection, %{}=opts) do
    case outbox_id do
      nil -> []
      _ -> Feeds.feed_activities([outbox_id], opts)
    end
  end

end
