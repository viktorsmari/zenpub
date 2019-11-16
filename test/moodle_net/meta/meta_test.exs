defmodule MoodleNet.MetaTest do
  use ExUnit.Case, async: true

  import ExUnit.Assertions
  import MoodleNet.Meta.Introspection, only: [ecto_schema_table: 1]
  import MoodleNet.Test.Faking
  alias MoodleNet.{Meta, Repo}
  alias MoodleNet.Meta.{
    Pointer,
    Table,
    TableService,
    TableNotFoundError,
  }
  alias MoodleNet.Actors.Actor
  alias MoodleNet.Communities.Community
  alias MoodleNet.Collections.Collection
  alias MoodleNet.Resources.Resource
  alias MoodleNet.Comments.{Comment, Thread}
  alias MoodleNet.Common.{
    Flag,
    Like,
    NotInTransactionError,
  }    
  alias MoodleNet.Peers.Peer
  alias MoodleNet.Users.User

  @known_schemas [Peer, Actor, User, Community, Collection, Resource, Comment, Thread, Flag, Like]
  @known_tables Enum.map(@known_schemas, &ecto_schema_table/1)
  @table_schemas Map.new(Enum.zip(@known_tables, @known_schemas))
  @expected_table_names Enum.sort(@known_tables)

  describe "MoodleNet.Meta.TableService" do
    
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      {:ok, %{}}
    end
    
    test "is fetching from good source data" do
      in_db = Repo.all(Table)
      |> Enum.map(&(&1.table))
      |> Enum.sort()
      assert @expected_table_names == in_db
    end

    @bad_table_names ["fizz", "buzz bazz"]

    test "returns results consistent with the source data" do
      # the database will be our source of truth
      tables = Repo.all(Table)
      assert Enum.count(tables) == Enum.count(@expected_table_names)
      # Every db entry must match up to our module metadata
      for t <- tables do
	assert %{id: id, table: table} = t
	# we must know about this schema to pair it up
	assert schema = Map.fetch!(@table_schemas, table)
	assert schema in @known_schemas
	t2 = %{ t | schema: schema }
	# There are 3 valid keys, 3 pairs of functions to check
	for key <- [schema, table, id] do
	  assert {:ok, t2} == TableService.lookup(key)
	  assert {:ok, id} == TableService.lookup_id(key)
	  assert {:ok, schema} == TableService.lookup_schema(key)
	  assert t2 == TableService.lookup!(key)
	  assert id == TableService.lookup_id!(key)
	  assert schema == TableService.lookup_schema!(key)
	end
      end
      for t <- @bad_table_names do
	assert {:error, %TableNotFoundError{table: t}} == TableService.lookup(t)
	assert %TableNotFoundError{table: t} == catch_throw(TableService.lookup!(t))
      end
    end
  end

  describe "MoodleNet.Meta.point_to!" do

    test "throws when not in a transaction" do
      expected_error = %NotInTransactionError{cause: "mn_peer"} 
      assert catch_throw(Meta.point_to!("mn_peer")) == expected_error
    end

    test "inserts a pointer when in a transaction" do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      Repo.transaction fn ->
	%Pointer{} = ptr = Meta.point_to!("mn_peer")
	assert ptr.table_id == TableService.lookup_id!("mn_peer")
	assert ptr.__meta__.state == :loaded
	assert ptr2 = Meta.find!(ptr.id)
	assert ptr2 == ptr
      end
    end
  end

  describe "MoodleNet.Meta.forge!" do

    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      {:ok, %{}}
    end

    test "forges a pointer for a peer" do
      peer = fake_peer!()
      pointer = Meta.forge!(peer)
      assert pointer.id == peer.id
      assert pointer.pointed == peer
      assert pointer.table_id == pointer.table.id
      assert pointer.table.table == "mn_peer"
    end

    test "forges a pointer for an actor" do
      actor = fake_actor!()
      pointer = Meta.forge!(actor)
      assert pointer.id == actor.id
      assert pointer.pointed == actor
      assert pointer.table_id == pointer.table.id
      assert pointer.table.table == "mn_actor"
    end

    test "forges a pointer for a user" do
      user = fake_user!()
      pointer = Meta.forge!(user)
      assert pointer.id == user.id
      assert pointer.pointed == user
      assert pointer.table_id == pointer.table.id
      assert pointer.table.table == "mn_user"
    end

    # TODO: others
    # @tag :skip
    # test "forges a pointer for a " do
    # end

    test "throws TableNotFoundError when given a non-meta table" do
      table = %Table{table: "power_of_greyskull"}
      assert %TableNotFoundError{table: Table} ==
	catch_throw(Meta.forge!(table))
    end
  end

  describe "MoodleNet.Meta.points_to!" do

    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      {:ok, %{}}
    end

    test "returns the Table the Pointer points to" do
      assert user = fake_user!()
      assert pointer = Meta.forge!(user)
      assert user_table = TableService.lookup!(User)
      assert table = Meta.points_to!(pointer)
      assert table == user_table
    end

    test "throws a TableNotFoundError if the Pointer doesn't point to a known table" do
      pointer = %Pointer{id: 123, table_id: 999}
      assert %TableNotFoundError{table: 999} =
        catch_throw(Meta.points_to!(pointer))
    end

  end

  describe "MoodleNet.Meta.assert_points_to!" do

    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      {:ok, %{}}
    end

    test "returns :ok if the Pointer points to the correct table" do
      assert user = fake_user!()
      assert pointer = Meta.forge!(user)
      assert :ok == Meta.assert_points_to!(pointer, User)
    end

    test "throws an error if the Pointer points to the wrong table" do
      assert user = fake_user!()
      assert pointer = Meta.forge!(user)
      assert :ok == Meta.assert_points_to!(pointer, User)
    end

    test "throws an error if the input isn't a known table name" do
      pointer = %Pointer{id: 123, table_id: :bibbity_bobbity_boo}
      assert %TableNotFoundError{table: :bibbity_bobbity_boo} =
        catch_throw(Meta.assert_points_to!(pointer, :bibbity_bobbity_boo))
    end

  end

  describe "MoodleNet.Meta.follow" do

    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(MoodleNet.Repo)
      {:ok, %{}}
    end

    test "follows pointers" do
      Repo.transaction fn ->
	assert peer = fake_peer!()
	assert pointer = Meta.find!(peer.id)
	assert table = Meta.points_to!(pointer)
	assert table.table == "mn_peer"
	assert table.schema == Peer
	assert table.id == pointer.table_id
	assert {:ok, peer2} = Meta.follow(pointer)
	assert peer3 = Meta.follow!(pointer)
	assert peer2 == peer
	assert peer3 == peer
      end
    end

    test "preload! can load one pointer" do
      Repo.transaction fn ->
	assert peer = fake_peer!()
	assert pointer = Meta.find!(peer.id)
	assert table = Meta.points_to!(pointer)
	assert table.table == "mn_peer"
	assert table.schema == Peer
	assert table.id == pointer.table_id
	assert pointer2 = Meta.preload!(pointer)
	assert pointer2.pointed == peer
	assert pointer2.id == pointer.id
	assert pointer2.table_id == pointer.table_id
	assert [pointer3] = Meta.preload!([pointer])
	assert pointer2 == pointer3
      end
    end

    test "preload! can load many pointers" do
      Repo.transaction fn ->
	assert peer = fake_peer!()
	assert peer2 = fake_peer!()
	assert pointer = Meta.find!(peer.id)
	assert pointer2 = Meta.find!(peer2.id)
	assert [pointer3, pointer4] = Meta.preload!([pointer, pointer2])
	assert pointer3.id == pointer.id
	assert pointer4.id == pointer2.id
	assert pointer3.table_id == pointer.table_id
	assert pointer4.table_id == pointer2.table_id
	assert pointer3.pointed == peer
	assert pointer4.pointed == peer2
      end
    end

    # TODO: merge antonis' work and figure out preloads
    test "preload! can load many pointers of many types" do
      Repo.transaction fn ->
	assert peer = fake_peer!()
	assert peer2 = fake_peer!()
	assert user = fake_user!()
	assert user2 = fake_user!()
	assert actor = fake_actor!()
	assert pointer = Meta.find!(peer.id)
	assert pointer2 = Meta.find!(peer2.id)
	assert pointer3 = Meta.find!(user.id)
	assert pointer4 = Meta.find!(user2.id)
	assert pointer5 = Meta.find!(actor.id)
	assert [pointer6, pointer7, pointer8, pointer9, pointer10] =
	  Meta.preload!([pointer, pointer2, pointer3, pointer4, pointer5])
	assert pointer6.id  == pointer.id
	assert pointer7.id  == pointer2.id
	assert pointer8.id  == pointer3.id
	assert pointer9.id  == pointer4.id
	assert pointer10.id == pointer5.id
	assert pointer6.pointed == peer
	assert pointer7.pointed == peer2
	pointed8 = Map.drop(pointer8.pointed, [:actor, :email_confirm_tokens])
	user3 = Map.drop(user, [:actor, :email_confirm_tokens])
	assert pointed8 == user3
	pointed9 = Map.drop(pointer9.pointed, [:actor, :email_confirm_tokens])
	user4 = Map.drop(user2, [:actor, :email_confirm_tokens])
	assert pointed9 == user4
	pointed10 = Map.drop(pointer10.pointed, [:current, :is_public, :latest_revision, :primary_language])
	actor2 = Map.drop(actor, [:current, :is_public, :latest_revision, :primary_language])
	assert actor2 == pointed10
      end
    end
  end

end