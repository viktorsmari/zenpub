# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Users.Queries do

  import Ecto.Query
  import MoodleNet.Common.Query, only: [match_admin: 0]
  alias MoodleNet.Actors
  alias MoodleNet.Follows.{Follow, FollowerCount}
  alias MoodleNet.Users.User

  def query(User), do: from(u in User, as: :user)

  def query(query, filters), do: filter(query(query), filters)

  defp join_to(q, spec, join_qualifier \\ :left)
  defp join_to(q, :actor, jq), do: join(q, jq, [user: u], assoc(u, :actor), as: :actor)
  defp join_to(q, :local_user, jq), do: join(q, jq, [user: u], assoc(u, :local_user), as: :local_user)

  defp join_to(q, {:follow, follower_id}, jq) do
    join q, jq, [user: u], f in Follow, as: :follow,
      on: u.id == f.context_id and f.creator_id == ^follower_id
  end

  defp join_to(q, :follower_count, jq) do
    join q, jq, [user: u],
      fc in FollowerCount, on: u.id == fc.context_id,
      as: :follower_count
  end

  defp join_to(q, {jq, join}, _), do: join_to(q, join, jq)

  @doc "Filter the query according to arbitrary criteria"
  def filter(query, filter_or_filters)

  def filter(q, filters) when is_list(filters), do: Enum.reduce(filters, q, &filter(&2, &1))

  def filter(q, :default), do: filter(q, deleted: false, join: :actor, join: :local_user, preload: :all)

  def filter(q, {:join, join}), do: join_to(q, join)


  def filter(q, {:user, match_admin()}), do: filter(q, deleted: false)
  def filter(q, {:user, nil}), do: filter(q, deleted: false, disabled: false, published: true)
  def filter(q, {:user, %User{id: id}}) do
    filter(q, join: {:follow, id}, disabled: false)
    |> where([follow: f, user: u], not is_nil(u.published_at) or not is_nil(f.id))
  end
  
  def filter(q, {:preset, :actor}) do
    filter(q, join: :actor, preload: :actor, deleted: false)
  end

  def filter(q, {:preset, :local_user}) do
    filter(q, join: :actor, join: :local_user, preload: :all, deleted: false)
  end

  def filter(q, {:deleted, nil}), do: where(q, [user: u], is_nil(u.deleted_at))
  def filter(q, {:deleted, :not_nil}), do: where(q, [user: u], not is_nil(u.deleted_at))
  def filter(q, {:deleted, false}), do: where(q, [user: u], is_nil(u.deleted_at))
  def filter(q, {:deleted, true}), do: where(q, [user: u], not is_nil(u.deleted_at))
  def filter(q, {:deleted, {:gte, %DateTime{}=time}}), do: where(q, [user: u], u.deleted_at >= ^time)
  def filter(q, {:deleted, {:lte, %DateTime{}=time}}), do: where(q, [user: u], u.deleted_at <= ^time)

  def filter(q, {:disabled, nil}), do: where(q, [user: u], is_nil(u.disabled_at))
  def filter(q, {:disabled, :not_nil}), do: where(q, [user: u], not is_nil(u.disabled_at))
  def filter(q, {:disabled, false}), do: where(q, [user: u], is_nil(u.disabled_at))
  def filter(q, {:disabled, true}), do: where(q, [user: u], not is_nil(u.disabled_at))
  def filter(q, {:disabled, {:gte, %DateTime{}=time}}), do: where(q, [user: u], u.disabled_at >= ^time)
  def filter(q, {:disabled, {:lte, %DateTime{}=time}}), do: where(q, [user: u], u.disabled_at <= ^time)

  def filter(q, {:published, nil}), do: where(q, [user: u], is_nil(u.published_at))
  def filter(q, {:published, :not_nil}), do: where(q, [user: u], not is_nil(u.published_at))
  def filter(q, {:published, false}), do: where(q, [user: u], is_nil(u.published_at))
  def filter(q, {:published, true}), do: where(q, [user: u], not is_nil(u.published_at))
  def filter(q, {:published, {:gte, %DateTime{}=time}}), do: where(q, [user: u], u.published_at >= ^time)
  def filter(q, {:published, {:lte, %DateTime{}=time}}), do: where(q, [user: u], u.published_at <= ^time)

  def filter(q, {:peer, peer}), do: Actors.Queries.filter(q, {:peer, peer})

  def filter(q, {:id, id}) when is_binary(id), do: where(q, [user: u], u.id == ^id)
  def filter(q, {:id, ids}) when is_list(ids), do: where(q, [user: u], u.id in ^ids)

  def filter(q, {:local_user, id}) when is_binary(id), do: where(q, [user: u], u.local_user_id == ^id)
  def filter(q, {:local_user, ids}) when is_list(ids), do: where(q, [user: u], u.local_user_id in ^ids)

  def filter(q, {:username, username}), do: Actors.Queries.filter(q, {:username, username})

  def filter(q, {:email, email}) when is_binary(email), do: where(q, [local_user: l], l.email == ^email)
  def filter(q, {:email, emails}) when is_list(emails), do: where(q, [local_user: l], l.email in ^emails)

  def filter(q, {:order, [asc: :created]}), do: order_by q, [user: u], [asc: u.id]
  def filter(q, {:order, [desc: :created]}), do: order_by q, [user: u], [desc: u.id]

  def filter(q, {:preload, :all}), do: preload(q, [actor: a, local_user: u], actor: a, local_user: u)
  def filter(q, {:preload, :actor}), do: preload(q, [actor: a], actor: a)
  def filter(q, {:preload, :local_user}), do: preload(q, [local_user: u], local_user: u)

end
