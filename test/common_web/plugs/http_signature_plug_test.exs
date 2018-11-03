defmodule MoodleNetWeb.Plugs.HTTPSignaturePlugTest do
  use MoodleNetWeb.ConnCase
  alias MoodleNetWeb.HTTPSignatures
  alias MoodleNetWeb.Plugs.HTTPSignaturePlug

  import Plug.Conn
  import Mock

  test "it call HTTPSignatures to check validity if the actor sighed it" do
    params = %{"actor" => "http://mastodon.example.org/users/admin"}
    conn = build_conn(:get, "/doesntmattter", params)

    with_mock HTTPSignatures, validate_conn: fn _ -> true end do
      conn =
        conn
        |> put_req_header(
          "signature",
          "keyId=\"http://mastodon.example.org/users/admin#main-key"
        )
        |> HTTPSignaturePlug.call(%{})

      assert conn.assigns.valid_signature == true
      assert called(HTTPSignatures.validate_conn(:_))
    end
  end

  test "bails out early if the signature isn't by the activity actor" do
    params = %{"actor" => "https://mst3k.interlinked.me/users/luciferMysticus"}
    conn = build_conn(:get, "/doesntmattter", params)

    with_mock HTTPSignatures, validate_conn: fn _ -> false end do
      conn =
        conn
        |> put_req_header(
          "signature",
          "keyId=\"http://mastodon.example.org/users/admin#main-key"
        )
        |> HTTPSignaturePlug.call(%{})

      assert conn.assigns.valid_signature == false
      refute called(HTTPSignatures.validate_conn(:_))
    end
  end
end
