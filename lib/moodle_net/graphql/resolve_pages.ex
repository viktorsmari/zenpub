defmodule MoodleNet.GraphQL.ResolvePages do
  @moduledoc """
  Encapsulates the flow of resolving a page in the presence of a
  single parent. We also currently use this as a stopgap while we
  finish implementing some things, trading speed for correctness.
  """

  @enforce_keys [:module, :fetcher, :context, :page_opts, :info]
  defstruct [
    :module, :fetcher, :context, :page_opts, :info,
    cursor_validators: [&Ecto.ULID.cast/1],
    single_opts: %{default_limit: 5, max_limit: 15},
    batch_opts: %{default_limit: 3, max_limit: 5},
    deep_opts: %{default_limit: 3, max_limit: 3},
    getter_fn: &Fields.getter/1,
  ]

  alias MoodleNet.GraphQL
  alias MoodleNet.GraphQL.ResolvePages
  import Absinthe.Resolution.Helpers, only: [async: 1, batch: 3]

  def run(%ResolvePages{info: info}=rp) do
    run(GraphQL.list_depth(info), Map.take(info, [:context]), rp)
  end

  defp run(0, info, rp), do: run_full(rp, info, rp.single_opts)
  defp run(1, info, rp), do: run_limit(rp, info, rp.batch_opts)
  defp run(_other, info, rp), do: run_limit(rp, info, rp.deep_opts)

  defp run_full(rp, info, opts) do
    with {:ok, opts} <- GraphQL.full_page_opts(rp.page_opts, rp.cursor_validators, opts) do
      async fn ->
        apply(rp.module, rp.fetcher, [opts, Map.take(info, [:context]), rp.context])
      end
    end
  end

  defp run_limit(rp, info, opts) do
    cond do
      function_exported?(rp.module, rp.fetcher, 2) -> batch_limit(rp, info, opts)
      function_exported?(rp.module, rp.fetcher, 3) -> unbatch_limit(rp, info, opts)
      true -> throw {:missing_fetcher, {rp.module, rp.fetcher, [2,3]}}
    end
  end

  # this is the fast path, we've actually written the scary query
  defp batch_limit(rp, info, opts) do
    with {:ok, opts} <- GraphQL.limit_page_opts(rp.page_opts, opts) do
      batch {rp.module, rp.fetcher, {opts, Map.take(info, [:context])}},
        rp.context, rp.getter_fn.(rp.context)
    end
  end

  # this is the slow path, we should write the scary query
  defp unbatch_limit(rp, info, opts) do
    with {:ok, opts} <- GraphQL.limit_page_opts(rp.page_opts, opts) do
      async fn ->
        apply(rp.module, rp.fetcher, [opts, Map.take(info, [:context]), rp.context])
      end
    end
  end

end
