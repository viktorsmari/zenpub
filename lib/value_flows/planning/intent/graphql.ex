# SPDX-License-Identifier: AGPL-3.0-only
defmodule ValueFlows.Planning.Intent.GraphQL do
  alias MoodleNet.{
    Activities,
    Communities,
    GraphQL,
    Repo,
    User
  }
  alias MoodleNet.GraphQL.{
    ResolveField,
    ResolveFields,
    ResolvePage,
    ResolvePages,
    ResolveRootPage,
    FetchPage,
    FetchPages,
    CommonResolver,
  }
  # alias MoodleNet.Resources.Resource
  alias MoodleNet.Common.Enums
  alias MoodleNetWeb.GraphQL.CommunitiesResolver

  alias ValueFlows.Planning.Intent
  alias ValueFlows.Planning.Intent.Intents
  alias ValueFlows.Planning.Intent.Queries

  # SDL schema import

  use Absinthe.Schema.Notation
  alias MoodleNetWeb.GraphQL.{CommonResolver}
  require Logger

  # import_sdl path: "lib/value_flows/graphql/schemas/planning.gql"

  ## resolvers

  def intent(%{id: id}, info) do
    ResolveField.run(
      %ResolveField{
        module: __MODULE__,
        fetcher: :fetch_intent,
        context: id,
        info: info,
      }
    )
  end

  def all_intents(page_opts, info) do
    ResolveRootPage.run(
      %ResolveRootPage{
        module: __MODULE__,
        fetcher: :fetch_intents,
        page_opts: page_opts,
        info: info,
        cursor_validators: [&(is_integer(&1) and &1 >= 0), &Ecto.ULID.cast/1], # popularity
      }
    )
  end

  ## fetchers

  def fetch_intent(info, id) do
    Intents.one(
      user: GraphQL.current_user(info),
      id: id,
      preload: :provider
    )
  end

  def fetch_intents(page_opts, info) do
    FetchPage.run(
      %FetchPage{
        queries: Queries,
        query: Intent,
        # preload: :provider,
        # cursor_fn: Intents.cursor(:followers),
        page_opts: page_opts,
        base_filters: [user: GraphQL.current_user(info)],
        # data_filters: [page: [desc: [followers: page_opts]]],
      }
    )
  end


  def community_edge(%Intent{community_id: id}, _, info) do
    ResolveFields.run(
      %ResolveFields{
        module: __MODULE__,
        fetcher: :fetch_community_edge,
        context: id,
        info: info,
      }
    )
  end

  def fetch_community_edge(_, ids) do
    {:ok, fields} = Communities.fields(&(&1.id), [:default, id: ids])
    fields
  end

  def fetch_provider_edge(%{provider: id}, _, info) do
    # IO.inspect(id)
    # Repo.preload(team_users: :user)
    CommonResolver.context_edge(%{context_id: id}, nil, info)
  end

  def fetch_receiver_edge(%{receiver: id}, _, info) do
    CommonResolver.context_edge(%{context_id: id}, nil, info)
  end


  ## finally the mutations...

  def create_intent(%{intent: attrs, in_scope_of_community_id: id}, info) do 
    # FIXME, need to do something like validate_thread_context to validate the provider/receiver agent ID
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, community} <- CommunitiesResolver.community(%{community_id: id}, info) do
        attrs = Map.merge(attrs, %{is_public: true, provider_id: attrs.provider})
        Intents.create(user, community, attrs)
      end
    end)
  end

  def create_intent(%{intent: attrs}, info) do
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        attrs = Map.merge(attrs, %{is_public: true, provider_id: attrs.provider})
        Intents.create(user, attrs)
      end
    end)
  end

  def update_intent(%{intent: changes, intent_id: id}, info) do
    Repo.transact_with(fn ->
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, intent} <- intent(%{intent_id: id}, info) do
        intent = Repo.preload(intent, :community)
        cond do
          user.local_user.is_instance_admin ->
        Intents.update(intent, changes)

          intent.creator_id == user.id ->
        Intents.update(intent, changes)

          intent.community.creator_id == user.id ->
        Intents.update(intent, changes)

          true -> GraphQL.not_permitted("update")
        end
      end
    end)
  end


  defp validate_agent(pointer) do
    if Pointers.table!(pointer).schema in valid_contexts() do
      :ok
    else
      GraphQL.not_permitted()
    end
  end

  defp valid_contexts() do
    [User, Organisation]
    # Keyword.fetch!(Application.get_env(:moodle_net, Threads), :valid_contexts)
  end

end
