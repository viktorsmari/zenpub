# SPDX-License-Identifier: AGPL-3.0-only
defmodule Geolocation.GraphQL do
  use Absinthe.Schema.Notation
  require Logger

  alias MoodleNet.{
    Activities,
    GraphQL,
    Repo,
    Meta.Pointers
  }

  alias MoodleNet.GraphQL.{
    ResolvePage,
    ResolvePages,
    ResolveField,
    ResolveFields,
    ResolveRootPage,
    FetchPage,
    FetchPages,
    CommonResolver
  }

  # alias MoodleNet.Resources.Resource
  alias MoodleNet.Common.Enums

  alias Geolocation
  alias Geolocation.Geolocations
  alias Geolocation.Queries
  alias Organisation

  # SDL schema import

  import_sdl(path: "lib/geolocation/geolocation.gql")

  ## resolvers

  def geolocation(%{id: id}, info) do
    ResolveField.run(%ResolveField{
      module: __MODULE__,
      fetcher: :fetch_geolocation,
      context: id,
      info: info
    })
  end

  def geolocations(page_opts, info) do
    ResolveRootPage.run(%ResolveRootPage{
      module: __MODULE__,
      fetcher: :fetch_geolocations,
      page_opts: page_opts,
      info: info,
      # popularity
      cursor_validators: [&(is_integer(&1) and &1 >= 0), &Ecto.ULID.cast/1]
    })
  end

  ## fetchers

  def fetch_geolocation(info, id) do
    with {:ok, geo} <- Geolocations.one(user: GraphQL.current_user(info), id: id, preload: :actor) do
      {:ok, Geolocations.populate_coordinates(geo)}
    end
  end

  def fetch_geolocations(page_opts, info) do
    page_result =
      FetchPage.run(%FetchPage{
        queries: Queries,
        query: Geolocation,
        cursor_fn: Geolocations.cursor(:followers),
        page_opts: page_opts,
        base_filters: [user: GraphQL.current_user(info)],
        data_filters: [page: [desc: [followers: page_opts]]]
      })

    with {:ok, %{edges: edges} = page} <- page_result do
      edges = Enum.map(edges, &Geolocations.populate_coordinates/1)
      {:ok, %{page | edges: edges}}
    end
  end

  def last_activity_edge(_, _, _info) do
    {:ok, DateTime.utc_now()}
  end

  def outbox_edge(%Geolocation{outbox_id: id}, page_opts, info) do
    ResolvePages.run(%ResolvePages{
      module: __MODULE__,
      fetcher: :fetch_outbox_edge,
      context: id,
      page_opts: page_opts,
      info: info
    })
  end

  def fetch_outbox_edge({page_opts, info}, id) do
    user = info.context.current_user

    {:ok, box} =
      Activities.page(
        & &1.id,
        & &1.id,
        page_opts,
        feed: id,
        table: default_outbox_query_contexts()
      )

    box
  end

  def fetch_outbox_edge(page_opts, info, id) do
    user = info.context.current_user

    Activities.page(
      & &1.id,
      page_opts,
      feed: id,
      table: default_outbox_query_contexts()
    )
  end

  defp default_outbox_query_contexts() do
    Application.fetch_env!(:moodle_net, Geolocations)
    |> Keyword.fetch!(:default_outbox_query_contexts)
  end

  ## finally the mutations...

  def create_geolocation(%{spatial_thing: attrs, in_scope_of: context_id}, info) do
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, pointer} <- Pointers.one(id: context_id),
           context = Pointers.follow!(pointer),
           attrs = Map.merge(attrs, %{is_public: true}),
           {:ok, g} <- Geolocations.create(user, context, attrs) do
        {:ok, %{spatial_thing: g}}
      end
    end)
  end

  def create_geolocation(%{spatial_thing: attrs}, info) do
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           attrs = Map.merge(attrs, %{is_public: true}),
           {:ok, g} <- Geolocations.create(user, attrs) do
        {:ok, %{spatial_thing: g}}
      end
    end)
  end

  def update_geolocation(%{spatial_thing: %{id: id} = changes}, info) do
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, geolocation} <- geolocation(%{id: id}, info) do
        geolocation = Repo.preload(geolocation, :context)

        resp =
          cond do
            user.local_user.is_instance_admin ->
              Geolocations.update(user, geolocation, changes)

            geolocation.creator_id == user.id ->
              Geolocations.update(user, geolocation, changes)

            #   geolocation.community.creator_id == user.id ->
            # Geolocations.update(geolocation, changes)

            true ->
              GraphQL.not_permitted("update")
          end

        with {:ok, geo} <- resp do
          {:ok, %{spatial_thing: geo}}
        end
      end
    end)
  end
end
