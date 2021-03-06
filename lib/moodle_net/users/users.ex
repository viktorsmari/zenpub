# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule MoodleNet.Users do
  @doc """
  A Context for dealing with Users.
  """
  require Logger
  alias MoodleNet.{
    Access,
    Activities,
    Actors,
    Blocks,
    Common,
    Communities,
    Collections,
    Features,
    Feeds,
    Flags,
    Follows,
    Likes,
    Repo,
    Resources,
    Threads,
  }
  alias MoodleNet.Feeds.FeedSubscriptions
  alias MoodleNet.Mail.{Email, MailService}
  alias MoodleNet.Users.{
    EmailConfirmToken,
    LocalUser,
    ResetPasswordToken,
    TokenAlreadyClaimedError,
    TokenExpiredError,
    Queries,
    User,
  }
  alias MoodleNet.Workers.APPublishWorker

  alias Ecto.Changeset

  @deleted_user_id "REA11YVERYDE1ETED1DENT1TY1"
  def deleted_user_id(), do: @deleted_user_id

  def one(filters), do: Repo.single(Queries.query(User, filters))

  def many(filters \\ []), do: {:ok, Repo.all(Queries.query(User, filters))}

  @doc """
  Registers a user:
  1. Splits attrs into actor and user fields
  2. Inserts user (because the access check isn't very good at crap emails yet)
  3. Checks the access
  4. Creates actor, email confirm token

  This is all controlled by options. An optional keyword list
  provided to this argument will be prepended to the application
  config under the path`[:moodle_net, MoodleNet.Users]`. Keys:

  `:public_registration` - boolean, default false. if false, accesss will be checked
  """
  @spec register(map, Keyword.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def register(attrs, opts \\ []) do
    Repo.transact_with(fn ->
      with {:ok, actor} <- Actors.create(attrs) do
        case actor.peer_id do
          nil -> register_local(actor, attrs, opts)
          _ -> register_remote(actor, attrs, opts)
        end
      end
    end)
  end

  defp register_local(actor, attrs, opts) do
    with {:ok, local_user} <- insert_local_user(attrs),
         :ok <- check_register_access(local_user.email, opts),
         {:ok, inbox} <- Feeds.create(),
         {:ok, outbox} <- Feeds.create(),
         attrs2 = Map.merge(attrs, %{inbox_id: inbox.id, outbox_id: outbox.id}),
         {:ok, user} <- Repo.insert(User.local_register_changeset(actor, local_user, attrs2)),
         {:ok, token} <- create_email_confirm_token(local_user) do
      user = %{user | actor: actor, local_user: %{ local_user | email_confirm_tokens: [token]}}
      Logger.info("Minted confirmation token for user: #{token.id}")
      user
      |> Email.welcome(token)
      |> MailService.maybe_deliver_later()

      {:ok, user}
    end
  end

  defp register_remote(actor, attrs, _opts) do
    with {:ok, outbox} <- Feeds.create(),
         attrs2 = Map.put(attrs, :outbox_id, outbox.id),
         {:ok, user} <- Repo.insert(User.register_changeset(actor, attrs2)) do
      {:ok, %{user | actor: actor}}
    end
  end

  defp should_check_register_access?(opts) do
    opts = opts ++ Application.get_env(:moodle_net, __MODULE__, [])
    not Keyword.get(opts, :public_registration, false)
  end

  defp check_register_access(email, opts) do
    if should_check_register_access?(opts),
      do: Access.check_register_access(email),
      else: :ok
  end

  defp insert_local_user(attrs) do
    with {:ok, local_user} <- Repo.insert(LocalUser.register_changeset(attrs)) do
      {:ok, %{local_user | password: nil}}
    end
  end

  defp create_email_confirm_token(%LocalUser{} = local_user),
    do: Repo.insert(EmailConfirmToken.create_changeset(local_user))

  @doc "Uses an email confirmation token, returns ok/error tuple"
  @spec claim_email_confirm_token(token :: any, DateTime.t()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def claim_email_confirm_token(token, now \\ DateTime.utc_now())

  def claim_email_confirm_token(token, %DateTime{} = now) when is_binary(token) do
    Repo.transact_with(fn ->
      with {:ok, token} <- Repo.fetch(EmailConfirmToken, token),
           :ok <- validate_token(token, :confirmed_at, now),
           {:ok, _} <- Repo.update(EmailConfirmToken.claim_changeset(token)),
           {:ok, user} <- one( join: :actor, join: :local_user, preload: :all,
                               local_user: token.local_user_id ),
           {:ok, user} <- confirm_email(user),
           :ok <- ap_publish("create", user) do
        {:ok, user}
      end
    end)
  end

  # use the email confirmation mechanism
  @doc """
  Verify a user's email address, allowing them to access their account.

  Note: this is for the benefit of the test suite. In normal use you
  should use the email confirmation mechanism.
  """
  @spec confirm_email(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def confirm_email(%User{} = user) do
    Repo.transact_with(fn ->
      with {:ok, local_user} <- Repo.update(LocalUser.confirm_email_changeset(user.local_user)) do
        user = preload_actor(%{ user | local_user: local_user})
        {:ok, user}
      end
    end)
  end

  @spec unconfirm_email(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def unconfirm_email(%User{} = user) do
    cs = LocalUser.unconfirm_email_changeset(user.local_user)
    Repo.transact_with(fn ->
      with {:ok, local_user} <- Repo.update(cs) do
        user = preload_actor(%{ user | local_user: local_user })
        {:ok, user}
      end
    end)
  end

  @spec request_password_reset(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def request_password_reset(%User{} = user) do
    cs = ResetPasswordToken.create_changeset(user.local_user)
    Repo.transact_with(fn ->
      with {:ok, token} <- Repo.insert(cs) do
        user
        |> Email.reset_password_request(token)
        |> MailService.maybe_deliver_later()

        {:ok, token}
      end
    end)
  end

  @spec claim_password_reset(token :: any, binary(), DateTime.t()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def claim_password_reset(token, password, now \\ DateTime.utc_now())

  def claim_password_reset(token, password, %DateTime{} = now)
  when is_binary(password) do
    Repo.transact_with(fn ->
      with {:ok, token} <- Repo.fetch(ResetPasswordToken, token),
           :ok <- validate_token(token, :reset_at, now),
           {:ok, local_user} <- Repo.fetch(LocalUser, token.local_user_id),
           {:ok, user} <- one(preset: :local_user, local_user: token.local_user_id),
           {:ok, _token} <- Repo.update(ResetPasswordToken.claim_changeset(token)),
           {:ok, _} <- Repo.update(LocalUser.update_changeset(local_user, %{password: password})) do
        user = preload_actor(%{ user | local_user: local_user })
        user
        |> Email.password_reset()
        |> MailService.maybe_deliver_later()
        {:ok, user}
      end
    end)
  end

  defp validate_token(token, claim_field, now) do
    cond do
      not is_nil(Map.fetch!(token, claim_field)) ->
        {:error, TokenAlreadyClaimedError.new()}

      :gt == DateTime.compare(now, token.expires_at) ->
        {:error, TokenExpiredError.new()}

      true ->
        :ok
    end
  end

  def update_by(filters, updates) do
    Repo.update_all(Queries.query(User, filters), set: updates)
  end

  @spec update(User.t(), map) :: {:ok, User.t()} | {:error, Changeset.t()}
  def update(%User{} = user, attrs) do
    Repo.transact_with(fn ->
      with {:ok, user} <- Repo.update(User.update_changeset(user, attrs)),
           {:ok, actor} <- Actors.update(user, user.actor, attrs),
           {:ok, local_user} <- Repo.update(LocalUser.update_changeset(user.local_user, attrs)),
           :ok <- ap_publish("update", user) do
        user = %{ user | local_user: local_user, actor: actor }
        {:ok, user}
      end
    end)
  end

  @spec update_remote(User.t(), map) :: {:ok, User.t()} | {:error, Changeset.t()}
  def update_remote(%User{} = user, attrs) do
    Repo.transact_with(fn ->
      with {:ok, user} <- Repo.update(User.update_changeset(user, attrs)),
           {:ok, actor} <- Actors.update(user, user.actor, attrs) do
        user = %{ user | actor: actor }
        {:ok, user}
      end
    end)
  end

  @spec soft_delete(User.t(), User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  # local user
  def soft_delete(deleter, %User{local_user: %LocalUser{}} = user) do
    Repo.transact_with(fn ->
      with {:ok, user2} <- Common.soft_delete(user),
           {:ok, local_user} <- Common.soft_delete(user.local_user),
           %{user: users, feed: feeds} = deleted_ids([user2]),
           :ok <- chase_delete(deleter, users, feeds),
           :ok <- ap_publish("delete", user) do
        user = %{ user2 | local_user: local_user, actor: user.actor}
        {:ok, user}
      end
    end)
  end

  # remote user
  def soft_delete(_deleter, %User{local_user: nil} = user) do
    Repo.transact_with(fn ->
      with {:ok, user2} <- Common.soft_delete(user),
          %{user: users, feed: feeds} = deleted_ids([user2]),
           :ok <- chase_delete(user, users, feeds),
           :ok <- ap_publish("delete", user) do
        user = %{ user2 | actor: user.actor }
        {:ok, user}
      end
    end)
  end

  # remote user, called by activitypub
  @spec soft_delete_remote(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def soft_delete_remote(%User{} = user) do
    Repo.transact_with(fn ->
      with {:ok, user2} <- Common.soft_delete(user),
          %{user: users, feed: feeds} = deleted_ids([user2]),
           :ok <- chase_delete(user, users, feeds) do
        user = %{ user2 | actor: user.actor }
        {:ok, user}
      end
    end)
  end

  @delete_by_filters [select: :delete, deleted: false]

  def soft_delete_by(%User{}=user, filters) do
    with {:ok, _} <-
      Repo.transact_with(fn ->
        {_, ids} = update_by(@delete_by_filters ++ filters, deleted_at: DateTime.utc_now())
        %{user: users, feed: feeds} = deleted_ids(ids)
        with :ok <- chase_delete(user, users, feeds) do
          ap_publish("delete", ids)
        end
      end), do: :ok
  end

  defp deleted_ids(records) do
    Enum.reduce(records, %{user: [], feed: []}, fn
      %{id: id, inbox_id: nil, outbox_id: nil}, acc ->
        Map.put(acc, :user, [id | acc.user])
      %{id: id, inbox_id: nil, outbox_id: o}, acc ->
        Map.merge(acc, %{user: [id | acc.user], feed: [o | acc.feed]})
      %{id: id, inbox_id: i, outbox_id: nil}, acc ->
        Map.merge(acc, %{user: [id | acc.user], feed: [i | acc.feed]})
      %{id: id, inbox_id: i, outbox_id: o}, acc ->
        Map.merge(acc, %{user: [id | acc.user], feed: [i, o | acc.feed]})
    end)
  end


  # TODO: some of these queries could be combined if we modified the queries modules
  defp chase_delete(user, users, []) do
    with :ok <- Activities.soft_delete_by(user, creator: users), # Not yet required but ok
         :ok <- Activities.soft_delete_by(user, context: users),
         :ok <- Blocks.soft_delete_by(user, creator: users),
         :ok <- Blocks.soft_delete_by(user, context: users),
         :ok <- Flags.soft_delete_by(user, context: users),
         :ok <- Follows.soft_delete_by(user, creator: users),
         :ok <- Follows.soft_delete_by(user, context: users),
         :ok <- Likes.soft_delete_by(user, creator: users),
         :ok <- Likes.soft_delete_by(user, context: users),
         :ok <- Threads.Comments.soft_delete_by(user, creator: users) do
      # Give away some things to the deleted user
      Communities.update_by(user, [creator: users], creator_id: @deleted_user_id)
      Collections.update_by(user, [creator: users], creator_id: @deleted_user_id)
      Resources.update_by(user, [creator: users], creator_id: @deleted_user_id)
      Features.update_by(user, [creator: users], creator_id: @deleted_user_id)
      Flags.update_by(user, [creator: users], creator_id: @deleted_user_id)
      :ok
    end
  end
  defp chase_delete(user, users, feeds) do
    with :ok <- Feeds.soft_delete_by(user, id: feeds), do: chase_delete(user, users, [])
  end

  @spec make_instance_admin(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def make_instance_admin(%User{} = user) do
    cs = LocalUser.make_instance_admin_changeset(user.local_user)
    Repo.transact_with(fn ->
      with {:ok, local_user} <- Repo.update(cs) do
        user = preload_actor(%{ user | local_user: local_user})
        {:ok, user}
      end
    end)
  end

  @spec unmake_instance_admin(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def unmake_instance_admin(%User{} = user) do
    cs = LocalUser.unmake_instance_admin_changeset(user.local_user)
    Repo.transact_with(fn ->
      with {:ok, local_user} <- Repo.update(cs) do
        user = preload_actor(%{ user | local_user: local_user})
        {:ok, user}
      end
    end)
  end

  def feed_subscriptions(%User{id: id}) do
    FeedSubscriptions.many(deleted: false, disabled: false, activated: true, subscriber: id)
  end

  def is_admin(%User{local_user: %LocalUser{is_instance_admin: val}}), do: val

  @spec preload(User.t(), Keyword.t()) :: User.t()
  def preload(user, opts \\ [])

  def preload(%User{} = user, opts) do
    Repo.preload(user, [:local_user, :actor], opts)
  end

  @spec preload_actor(User.t(), Keyword.t()) :: User.t()
  def preload_actor(%User{} = user, opts \\ []) do
    Repo.preload(user, :actor, opts)
  end

  @spec preload_local_user(User.t(), Keyword.t()) :: User.t()
  def preload_local_user(%User{} = user, opts \\ []) do
    Repo.preload(user, :local_user, opts)
  end

  defp ap_publish(verb, users) when is_list(users) do
    APPublishWorker.batch_enqueue(verb, users)
    :ok
  end

  defp ap_publish(verb, %{actor: %{peer_id: nil}}=user) do
    APPublishWorker.enqueue(verb, %{"context_id" => user.id})
    :ok
  end

  defp ap_publish(_, _), do: :ok

  @doc false
  def default_inbox_query_contexts() do
    Application.fetch_env!(:moodle_net, __MODULE__)
    |> Keyword.fetch!(:default_inbox_query_contexts)
  end

  @doc false
  def default_outbox_query_contexts() do
    Application.fetch_env!(:moodle_net, __MODULE__)
    |> Keyword.fetch!(:default_outbox_query_contexts)
  end

end
