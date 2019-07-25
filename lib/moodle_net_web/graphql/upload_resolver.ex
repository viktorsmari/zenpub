defmodule MoodleNetWeb.GraphQL.UploadResolver do
  import MoodleNetWeb.GraphQL.MoodleNetSchema
  alias ActivityPub.SQL.Query
  alias MoodleNet.Accounts
  alias MoodleNetWeb.Uploaders.{Avatar, Background}

  def upload_icon(params, info) do
    # FIXME: this isn't authorization
    with {:ok, _} <- current_actor(info) do
      do_upload(Avatar, :icon, params)
    end
  end

  def upload_image(params, info) do
    with {:ok, _} <- current_actor(info) do
      do_upload(Background, :image, params)
    end
  end

  defp do_upload(uploader, field_name, %{local_id: local_id, image: image}) do
    with {:ok, object} <- fetch_object_by_id(local_id),
         image_object = fetch_image_field(object, field_name),
         # FIXME: relative URL's are no good for federation
         {:ok, url} <- uploader.store(image),
         {:ok, _} <- ActivityPub.update(object, url: url) do
      {:ok, url}
    end
  end

  defp fetch_object_by_id(local_id) do
    case fetch(local_id, "Object") do
      # TODO: move this to fetch/2
      {:ok, nil} -> {:error, :not_found}
      {:ok, object} -> {:ok, object}
      error -> error
    end
  end

  defp fetch_image_field(object, field_name) do
    Query.new()
    |> Query.belongs_to(field_name, object)
    |> Query.one()
  end
end
