defmodule Pleroma.Web.Router do
  use Pleroma.Web, :router

  alias Pleroma.{Repo, User, Web.Router}

  @instance Application.get_env(:pleroma, :instance)
  @federating Keyword.get(@instance, :federating)
  @allow_relay Keyword.get(@instance, :allow_relay)
  @public Keyword.get(@instance, :public)
  @registrations_open Keyword.get(@instance, :registrations_open)

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.BasicAuthDecoderPlug)
    plug(Pleroma.Plugs.UserFetcherPlug)
    plug(Pleroma.Plugs.SessionAuthenticationPlug)
    plug(Pleroma.Plugs.LegacyAuthenticationPlug)
    plug(Pleroma.Plugs.AuthenticationPlug)
    plug(Pleroma.Plugs.UserEnabledPlug)
    plug(Pleroma.Plugs.SetUserSessionIdPlug)
    plug(Pleroma.Plugs.EnsureUserKeyPlug)
  end

  pipeline :authenticated_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.BasicAuthDecoderPlug)
    plug(Pleroma.Plugs.UserFetcherPlug)
    plug(Pleroma.Plugs.SessionAuthenticationPlug)
    plug(Pleroma.Plugs.LegacyAuthenticationPlug)
    plug(Pleroma.Plugs.AuthenticationPlug)
    plug(Pleroma.Plugs.UserEnabledPlug)
    plug(Pleroma.Plugs.SetUserSessionIdPlug)
    plug(Pleroma.Plugs.EnsureAuthenticatedPlug)
  end

  pipeline :mastodon_html do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.BasicAuthDecoderPlug)
    plug(Pleroma.Plugs.UserFetcherPlug)
    plug(Pleroma.Plugs.SessionAuthenticationPlug)
    plug(Pleroma.Plugs.LegacyAuthenticationPlug)
    plug(Pleroma.Plugs.AuthenticationPlug)
    plug(Pleroma.Plugs.UserEnabledPlug)
    plug(Pleroma.Plugs.SetUserSessionIdPlug)
    plug(Pleroma.Plugs.EnsureUserKeyPlug)
  end

  pipeline :pleroma_html do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.BasicAuthDecoderPlug)
    plug(Pleroma.Plugs.UserFetcherPlug)
    plug(Pleroma.Plugs.SessionAuthenticationPlug)
    plug(Pleroma.Plugs.AuthenticationPlug)
    plug(Pleroma.Plugs.EnsureUserKeyPlug)
  end

  pipeline :well_known do
    plug(:accepts, ["json", "jrd+json", "xml", "xrd+xml"])
  end

  pipeline :config do
    plug(:accepts, ["json", "xml"])
  end

  pipeline :oauth do
    plug(:accepts, ["html", "json"])
  end

  pipeline :pleroma_api do
    plug(:accepts, ["html", "json"])
  end

  scope "/oauth", Pleroma.Web.OAuth do
    get("/authorize", OAuthController, :authorize)
    post("/authorize", OAuthController, :create_authorization)
    post("/token", OAuthController, :token_exchange)
    post("/revoke", OAuthController, :token_revoke)
  end

  scope "/api", Pleroma.Web do
    pipe_through(:config)

  end

  pipeline :ap_relay do
    plug(:accepts, ["activity+json"])
  end

  pipeline :activitypub do
    plug(:accepts, ["activity+json"])
    plug(Pleroma.Web.Plugs.HTTPSignaturePlug)
  end

  scope "/", Pleroma.Web.ActivityPub do
    pipe_through(:ap_relay)

    get("/objects/:uuid", ActivityPubController, :object)
    get("/users/:nickname", ActivityPubController, :user)
    get("/users/:nickname/followers", ActivityPubController, :followers)
    get("/users/:nickname/following", ActivityPubController, :following)
    get("/users/:nickname/outbox", ActivityPubController, :outbox)
  end

  scope "/", Pleroma.Web.MastodonAPI do
    pipe_through(:mastodon_html)

    get("/register", MastodonAPIController, :register)
    post("/register", MastodonAPIController, :register_post)

    get("/web/login", MastodonAPIController, :login)
    post("/web/login", MastodonAPIController, :login_post)

    get("/web/*path", MastodonAPIController, :index)

    delete("/auth/sign_out", MastodonAPIController, :logout)
  end

  if @federating do
    if @allow_relay do
      scope "/relay", Pleroma.Web.ActivityPub do
        pipe_through(:ap_relay)
        get("/", ActivityPubController, :relay)
      end
    end

    scope "/", Pleroma.Web.ActivityPub do
      pipe_through(:activitypub)
      post("/users/:nickname/inbox", ActivityPubController, :inbox)
      post("/inbox", ActivityPubController, :inbox)
    end

    scope "/.well-known", Pleroma.Web do
      pipe_through(:well_known)

      get("/host-meta", WebFinger.WebFingerController, :host_meta)
      get("/webfinger", WebFinger.WebFingerController, :webfinger)
      get("/nodeinfo", Nodeinfo.NodeinfoController, :schemas)
    end

    scope "/nodeinfo", Pleroma.Web do
      get("/:version", Nodeinfo.NodeinfoController, :nodeinfo)
    end
  end

  pipeline :remote_media do
    plug(:accepts, ["html"])
  end

  scope "/proxy/", Pleroma.Web.MediaProxy do
    pipe_through(:remote_media)
    get("/:sig/:url", MediaProxyController, :remote)
  end

  scope "/", Fallback do
    get("/registration/:token", RedirectController, :registration_page)
    get("/*path", RedirectController, :redirector)
  end
end

defmodule Fallback.RedirectController do
  use Pleroma.Web, :controller

  def redirector(conn, _params) do
    if Mix.env() != :test do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, "priv/static/index.html")
    end
  end

  def registration_page(conn, params) do
    redirector(conn, params)
  end
end
