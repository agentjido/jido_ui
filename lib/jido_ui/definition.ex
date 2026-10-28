defmodule Jido.UI.Definition do
  @moduledoc """
  The canonical, portable UI value produced by DSL, maps, and JSON.

  A Definition has no Agent identity, revision, or runtime state.
  """

  alias Jido.UI.{Child, Error, Intent, JSON, Node}

  @fields %{
    name: Zoi.string() |> Zoi.min(1),
    description: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
    vsn: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
    catalog: Zoi.string() |> Zoi.min(1),
    root: Zoi.string() |> Zoi.min(1),
    nodes: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Node)) |> Zoi.default(%{}),
    intents: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Intent)) |> Zoi.default(%{}),
    metadata: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Definition schema."
  def schema, do: @schema

  @doc "Creates one canonical Definition."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = definition), do: validate(definition)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with {:ok, attrs} <- JSON.normalize_object(attrs, Map.keys(@fields)),
         {:ok, attrs} <- normalize_map(attrs, :nodes, &Node.new/1),
         {:ok, attrs} <- normalize_map(attrs, :intents, &Intent.new/1),
         {:ok, definition} <- parse(attrs),
         {:ok, definition} <- validate(definition) do
      {:ok, definition}
    end
  end

  def new(value), do: invalid(:invalid_definition, "Definition is invalid", %{value: value})

  @doc "Creates one Definition or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, definition} -> definition
      {:error, error} -> raise error
    end
  end

  @doc "Validates Definition identity, references, and graph shape."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = definition) do
    with {:ok, definition} <- parse(definition),
         :ok <- JSON.validate(definition.metadata, [:metadata]),
         :ok <- matching_ids(definition.nodes, :nodes),
         :ok <- matching_ids(definition.intents, :intents),
         :ok <- root_exists(definition),
         :ok <- local_references(definition),
         :ok <- connected_local_graph(definition) do
      {:ok, definition}
    end
  end

  def validate(value) do
    invalid(:invalid_definition, "Expected a Definition", %{value: value})
  end

  defp normalize_map(attrs, field, constructor) do
    key = key_for(attrs, field)
    values = Map.get(attrs, key, %{})

    if is_map(values) and not is_struct(values) do
      Enum.reduce_while(values, {:ok, %{}}, fn {id, value}, {:ok, result} ->
        value = put_id(value, id)

        case constructor.(value) do
          {:ok, item} -> {:cont, {:ok, Map.put(result, id, item)}}
          {:error, error} -> {:halt, {:error, Error.prepend_path(error, [field, id])}}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Map.put(attrs, key, values)}
        error -> error
      end
    else
      invalid(:invalid_definition, "Definition collection must be a map", %{field: field})
    end
  end

  defp put_id(%_{} = value, _id), do: value
  defp put_id(value, id) when is_map(value), do: Map.put_new(value, id_key(value), id)
  defp put_id(value, _id), do: value

  defp id_key(value), do: if(Map.has_key?(value, "id"), do: "id", else: :id)

  defp key_for(attrs, field) do
    string = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, field) -> field
      Map.has_key?(attrs, string) -> string
      true -> field
    end
  end

  defp parse(value) do
    schema = if is_struct(value, __MODULE__), do: @schema, else: @attrs_schema

    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = definition} -> {:ok, definition}
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid(:invalid_definition, "Definition is invalid", %{issues: issues})
    end
  end

  defp matching_ids(values, field) do
    case Enum.find(values, fn {id, value} -> id != value.id end) do
      nil ->
        :ok

      {id, value} ->
        invalid(:identity_mismatch, "Definition key does not match value ID", %{
          field: field,
          key: id,
          id: value.id
        })
    end
  end

  defp root_exists(%__MODULE__{root: root, nodes: nodes}) do
    if Map.has_key?(nodes, root) do
      :ok
    else
      invalid(:unknown_root, "Definition root Node does not exist", %{root: root})
    end
  end

  defp local_references(definition) do
    Enum.reduce_while(definition.nodes, :ok, fn {_id, node}, :ok ->
      with :ok <- child_node_references(node, definition.nodes),
           :ok <- intent_references(node, definition.intents) do
        {:cont, :ok}
      else
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp child_node_references(node, nodes) do
    case Enum.find(node.children, fn
           %Child{kind: :node, id: id} -> not Map.has_key?(nodes, id)
           %Child{kind: :region} -> false
         end) do
      nil ->
        :ok

      %Child{id: id} ->
        invalid(:unknown_node, "Node has an unknown child", %{node: node.id, child: id})
    end
  end

  defp intent_references(node, intents) do
    case Enum.find(node.events, fn {_event, intent_id} -> not Map.has_key?(intents, intent_id) end) do
      nil ->
        :ok

      {event, intent_id} ->
        invalid(:unknown_intent, "Node event has an unknown Intent", %{
          node: node.id,
          event: event,
          intent: intent_id
        })
    end
  end

  defp connected_local_graph(definition) do
    case visit_node(definition.root, definition.nodes, MapSet.new(), MapSet.new()) do
      {:ok, visited} ->
        if map_size(definition.nodes) == MapSet.size(visited) do
          :ok
        else
          missing = Map.keys(definition.nodes) -- MapSet.to_list(visited)
          invalid(:unreachable_node, "Definition has unreachable Nodes", %{nodes: missing})
        end

      error ->
        error
    end
  end

  defp visit_node(id, nodes, visited, active) do
    cond do
      MapSet.member?(active, id) ->
        invalid(:node_cycle, "Definition Node graph has a cycle", %{node: id})

      MapSet.member?(visited, id) ->
        {:ok, visited}

      true ->
        active = MapSet.put(active, id)
        visited = MapSet.put(visited, id)

        nodes[id].children
        |> Enum.filter(&match?(%Child{kind: :node}, &1))
        |> Enum.reduce_while({:ok, visited}, fn %Child{id: child}, {:ok, result} ->
          case visit_node(child, nodes, result, active) do
            {:ok, result} -> {:cont, {:ok, result}}
            error -> {:halt, error}
          end
        end)
    end
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
