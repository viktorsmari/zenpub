defmodule Pleroma.Stats do
  use Agent
  import Ecto.Query
  alias Pleroma.{User, Repo, Activity}

  def start_link do
    agent = Agent.start_link(fn -> {[], %{}} end, name: __MODULE__)
    schedule_update()
    agent
  end

  def get_stats do
    Agent.get(__MODULE__, fn {_, stats} -> stats end)
  end

  def get_peers do
    Agent.get(__MODULE__, fn {peers, _} -> peers end)
  end

  def schedule_update do
    update_stats()
    spawn(fn ->
      Process.sleep(1000 * 60 * 60 * 1) # 1 hour
      schedule_update()
    end)
  end

  def update_stats do
    peers = from(u in Pleroma.User,
      select: fragment("?->'host'", u.info),
      where: u.local != ^true)
    |> Repo.all() |> Enum.uniq()
    domain_count = Enum.count(peers)
    status_query = from p in Activity,
      where: p.local == ^true,
      where: fragment("?->'object'->>'type' = ?", p.data, ^"Note")
    status_count = Repo.aggregate(status_query, :count, :id)
    user_count = Repo.aggregate(User.local_user_query, :count, :id)
    Agent.update(__MODULE__, fn _ ->
      {peers, %{domain_count: domain_count, status_count: status_count, user_count: user_count}}
    end)
  end
end