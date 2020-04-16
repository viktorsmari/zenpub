defmodule ValueFlows.Agent.Hydration do

  alias MoodleNetWeb.GraphQL.{
    ActorsResolver,
    UploadResolver
  }


  def hydrate(blueprint) do
    %{
      agent: [
        resolve_type: &ValueFlows.Agent.GraphQL.agent_resolve_type/2,
      ],
      person: %{
        canonical_url: [
          resolve: &ActorsResolver.canonical_url_edge/3
        ],
        display_username: [
          resolve: &ActorsResolver.display_username_edge/3
        ],
        image: [
          resolve: &UploadResolver.image_content_edge/3
        ]
      },
      # person: [
      #   is_type_of: &ValueFlows.Agent.GraphQL.person_is_type_of/2
      # ],
      # organization: [
      #   is_type_of: &ValueFlows.Agent.GraphQL.organization_is_type_of/2
      # ],
      agent_query: %{
        all_agents: [
          resolve: &ValueFlows.Agent.GraphQL.all_agents/3
        ],
        agent: [
          resolve: &ValueFlows.Agent.GraphQL.agent/2,
          
        ],
        person: [
          resolve: &ValueFlows.Agent.GraphQL.person/2
        ],
        all_people: [
          resolve: &ValueFlows.Agent.GraphQL.people/2
        ],
      },
      # mutation: %{
      #   failing_thing: [
      #     resolve: &__MODULE__.resolve_failing_thing/3
      #   ]
      # }
    }
  end





end