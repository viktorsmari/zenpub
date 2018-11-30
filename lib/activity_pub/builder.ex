defmodule ActivityPub.Builder do
  @moduledoc false

  alias ActivityPub.{Entity, Context, Types, Metadata}
  alias ActivityPub.BuildError
  alias ActivityPub.UrlBuilder

  require ActivityPub.Guards, as: APG

  def new(params \\ %{})
  def new(params) when is_list(params), do: params |> Enum.into(%{}) |> new()

  def new(params) when is_map(params),
    do: build(:new, params, nil, nil)

  def parse(_params) do
  end

  def load(_params) do
  end

  defp build(:new, entity, _, _) when APG.is_entity(entity), do: {:ok, entity}

  defp build(:new, id, parent, _) when is_binary(id) and not is_nil(parent) do
    meta = Metadata.not_loaded()
    {:ok, %{__ap__: meta, id: id}}
  end

  defp build(:new, params, parent, parent_key) when is_map(params),
    do: build_new(normalize_keys(params), parent, parent_key)

  defp build(:new, value, _, parent_key),
    do: {:error, %BuildError{path: [parent_key], value: value, message: "is invalid"}}

  defp build_new(%{"id" => value}, _, parent_key) do
    msg = "is an autogenerated field"
    build_error("id", value, msg, parent_key)
  end

  defp build_new(params, parent, parent_key) when is_map(params) do
    {raw_context, params} = Map.pop(params, "@context")
    {raw_type, params} = Map.pop(params, "type")

    with {:ok, context} <- context(:new, raw_context, parent),
         {:ok, type} <- type(:new, raw_type),
         meta = Metadata.new(type),
         entity = %{__ap__: meta, id: nil, type: type, "@context": context},
         {:ok, entity, params} <- merge_aspects_fields(entity, params),
         {:ok, entity, extension_fields} <- merge_aspects_assocs(entity, params),
         entity = Map.merge(entity, extension_fields) do
      {:ok, entity}
    else
      {:error, %BuildError{} = e} ->
        e = insert_parent_keys(e, parent_key)
        {:error, e}
    end
  end

  defp merge_aspects_fields(entity, params) do
    entity
    |> Entity.aspects()
    |> Enum.reduce({:ok, entity, params}, &cast_fields(&2, &1))
  end

  defp cast_fields({:ok, entity, params}, aspect) do
    Enum.reduce(
      aspect.__aspect__(:fields),
      {:ok, entity, params},
      &cast_field(&2, aspect.__aspect__(:type, &1), &1)
    )
  end

  defp cast_fields(ret, _aspect), do: ret

  defp cast_field({:ok, entity, params}, ActivityPub.LanguageValueType, key) do
    lang = entity[:"@context"].language

    map_key = "#{key}_map"
    param_key = to_string(key)
    # FIXME if it has the two keys is an error
    value = Map.get(params, map_key) || Map.get(params, param_key)
    params = params |> Map.delete(param_key) |> Map.delete(map_key)

    with {:ok, value} <- ActivityPub.LanguageValueType.cast(value, lang) do
      {:ok, Map.put(entity, key, value), params}
    else
      :error ->
        error = %BuildError{path: [param_key], value: value, message: "is invalid"}
        {:error, error}
    end
  end

  defp cast_field({:ok, entity, params}, type, key) do
    key_str = to_string(key)
    {value, params} = Map.pop(params, key_str)

    case cast_value(type, value) do
      {:ok, value} ->
        {:ok, Map.put(entity, key, value), params}

      :error ->
        error = %BuildError{path: [key_str], value: value, message: "is invalid"}
        {:error, error}
    end
  end

  defp cast_field(error, _, _), do: error

  defp cast_value(type, value) do
    # This is to avoid nil values not being cast
    if Ecto.Type.primitive?(type),
      do: Ecto.Type.cast(type, value),
      else: type.cast(value)
  end

  defp merge_aspects_assocs(entity, params) do
    entity
    |> Entity.aspects()
    |> Enum.reduce({:ok, entity, params}, &cast_assocs(&2, &1))
  end

  defp cast_assocs({:ok, entity, params}, aspect) do
    try do
      Enum.reduce(
        aspect.__aspect__(:associations),
        {:ok, entity, params},
        &cast_assoc(&2, aspect.__aspect__(:association, &1), &1)
      )
    catch
      {:error, _} = ret -> ret
    end
  end

  defp cast_assocs(error, _aspect), do: error

  defp cast_assoc({:ok, entity, params}, assoc_info, assoc_name) do
    assoc_name_str = to_string(assoc_name)
    {raw_assoc, params} = Map.pop(params, assoc_name_str)

    case assoc_info.cardinality do
      :one ->
        cast_single_assoc(raw_assoc, entity, assoc_name_str)

      :many ->
        cast_many_assoc(raw_assoc, entity, assoc_name_str)
    end
    |> case do
      {:ok, assoc} ->
        {:ok, Map.put(entity, assoc_name, assoc), params}

      error ->
        error
    end
  end

  defp cast_assoc(error, _, _), do: error

  defp cast_many_assoc(raw_assocs, entity, assoc_name_str) do
    assocs =
      raw_assocs
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce([], fn {raw_assoc, index}, acc ->
        case cast_single_assoc(raw_assoc, entity, "#{assoc_name_str}.#{index}") do
          {:ok, nil} -> acc
          {:ok, assoc} -> [assoc | acc]
          {:error, _} = error -> throw(error)
        end
      end)
      |> Enum.reverse()

    {:ok, assocs}
  end

  defp cast_single_assoc(nil, _, _), do: {:ok, nil}
  defp cast_single_assoc(params, entity, key),
    do: build(:new, params, entity, key)

  defp context(:new, nil, nil), do: {:ok, Context.default()}
  defp context(:new, nil, parent), do: {:ok, parent[:"@context"]}
  defp context(:new, raw_context, _parent), do: Context.build(raw_context)

  defp type(:new, raw_type), do: Types.build(raw_type)

  def build_error(key, value, message, parent_key) do
    e =
      %BuildError{path: [key], value: value, message: message}
      |> insert_parent_keys(parent_key)

    {:error, e}
  end

  defp insert_parent_keys(%BuildError{} = e, nil), do: e

  defp insert_parent_keys(%BuildError{} = e, parent_key),
    do: %{e | path: [parent_key | e.path]}

  defp normalize_keys(%{} = params) do
    params
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{}, fn
      {"@" <> key, value} ->
        key = key |> Recase.to_snake()
        {"@#{key}", value}

      {key, value} ->
        key = key |> Recase.to_snake()
        {key, value}
    end)
  end
end
