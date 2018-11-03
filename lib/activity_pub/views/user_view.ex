defmodule ActivityPub.UserView do
  use MoodleNetWeb, :view
  alias MoodleNet.User
  alias MoodleNet.Repo
  alias ActivityPub
  alias ActivityPub.Transmogrifier
  alias ActivityPub.Utils
  import Ecto.Query

  def render("user.json", %{user: user}) do
    {:ok, user} = MoodleNet.Signature.ensure_keys_present(user)
    {:ok, _, public_key} = MoodleNet.Signature.keys_from_pem(user.info["keys"])
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_key = :public_key.pem_encode([public_key])

    %{
      "id" => user.ap_id,
      "type" => "Person",
      "following" => "#{user.ap_id}/following",
      "followers" => "#{user.ap_id}/followers",
      "inbox" => "#{user.ap_id}/inbox",
      "outbox" => "#{user.ap_id}/outbox",
      "preferredUsername" => user.nickname,
      "name" => user.name,
      "summary" => user.bio,
      "url" => user.ap_id,
      "manuallyApprovesFollowers" => user.info["locked"] || false,
      "publicKey" => %{
        "id" => "#{user.ap_id}#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => public_key
      },
      "endpoints" => %{
        "sharedInbox" => "#{MoodleNetWeb.Endpoint.url()}/inbox"
      },
      "icon" => %{
        "type" => "Image",
        "url" => User.avatar_url(user)
      },
      "image" => %{
        "type" => "Image",
        "url" => User.banner_url(user)
      },
      "tag" => user.info["source_data"]["tag"] || []
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user, page: page}) do
    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    collection(following, "#{user.ap_id}/following", page)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user}) do
    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    %{
      "id" => "#{user.ap_id}/following",
      "type" => "OrderedCollection",
      "totalItems" => length(following),
      "first" => collection(following, "#{user.ap_id}/following", 1)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user, page: page}) do
    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    collection(followers, "#{user.ap_id}/followers", page)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user}) do
    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    %{
      "id" => "#{user.ap_id}/followers",
      "type" => "OrderedCollection",
      "totalItems" => length(followers),
      "first" => collection(followers, "#{user.ap_id}/followers", 1)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("outbox.json", %{user: user, max_id: max_qid}) do
    # XXX: technically note_count is wrong for this, but it's better than nothing
    info = User.user_info(user)

    params = %{
      "limit" => "10"
    }

    params =
      if max_qid != nil do
        Map.put(params, "max_id", max_qid)
      else
        params
      end

    activities = ActivityPub.fetch_user_activities(user, nil, params)
    min_id = Enum.at(Enum.reverse(activities), 0).id
    max_id = Enum.at(activities, 0).id

    collection =
      Enum.map(activities, fn act ->
        {:ok, data} = Transmogrifier.prepare_outgoing(act.data)
        data
      end)

    iri = "#{user.ap_id}/outbox"

    page = %{
      "id" => "#{iri}?max_id=#{max_id}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => info.note_count,
      "orderedItems" => collection,
      "next" => "#{iri}?max_id=#{min_id - 1}"
    }

    if max_qid == nil do
      %{
        "id" => iri,
        "type" => "OrderedCollection",
        "totalItems" => info.note_count,
        "first" => page
      }
      |> Map.merge(Utils.make_json_ld_header())
    else
      page |> Map.merge(Utils.make_json_ld_header())
    end
  end

  def collection(collection, iri, page, total \\ nil) do
    offset = (page - 1) * 10
    items = Enum.slice(collection, offset, 10)
    items = Enum.map(items, fn user -> user.ap_id end)
    total = total || length(collection)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => items
    }

    if offset < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    end
  end
end
