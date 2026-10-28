defmodule Jido.UI.Region do
  @moduledoc "A committed UI Projection owned by one exact Jido Agent boundary."

  alias Jido.UI.{Definition, Error, JSON, Node}
  alias Jido.UI.Region.Action

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    owner: Zoi.struct(Jido.Agent.Ref),
    revision: Zoi.integer() |> Zoi.min(0),
    definition: Zoi.struct(Definition),
    nodes: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Node)) |> Zoi.default(%{}),
    data: Zoi.map() |> Zoi.default(%{}),
    actions: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Action)) |> Zoi.default(%{}),
    status: Zoi.enum([:ready, :busy, :waiting, :complete, :error]) |> Zoi.default(:ready),
    metadata: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Region schema."
  def schema, do: @schema

  @doc "Creates one Agent-owned Region."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = region), do: validate(region)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with {:ok, attrs} <- normalize_owner(attrs),
         {:ok, attrs} <- normalize_value(attrs, :definition, &Definition.new/1),
         {:ok, attrs} <- normalize_map(attrs, :nodes, &Node.new/1),
         {:ok, attrs} <- normalize_map(attrs, :actions, &Action.new/1),
         {:ok, region} <- parse(attrs),
         {:ok, region} <- validate(region) do
      {:ok, region}
    end
  end

  def new(value), do: invalid(:invalid_region, "Region is invalid", %{value: value})

  @doc "Creates one Region or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, region} -> region
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Region and its Agent boundary."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = region) do
    with {:ok, region} <- parse(region),
         {:ok, _owner} <- Jido.Agent.Ref.validate(region.owner),
         {:ok, _definition} <- Definition.validate(region.definition),
         :ok <- JSON.validate(region.data, [:data]),
         :ok <- JSON.validate(region.metadata, [:metadata]),
         :ok <- matching_ids(region.nodes, :nodes),
         :ok <- matching_ids(region.actions, :actions),
         :ok <- matching_definition(region) do
      {:ok, region}
    end
  end

  def validate(value), do: invalid(:invalid_region, "Expected a Region", %{value: value})

  @doc "Returns the bound root Node."
  @spec root(t()) :: Node.t()
  def root(%__MODULE__{} = region), do: Map.fetch!(region.nodes, region.definition.root)

  @doc "Returns the Catalog ID."
  @spec catalog(t()) :: String.t()
  def catalog(%__MODULE__{} = region), do: region.definition.catalog

  @doc "Returns mounted child Region IDs."
  @spec child_regions(t()) :: [String.t()]
  def child_regions(%__MODULE__{} = region) do
    region.nodes
    |> Map.values()
    |> Enum.flat_map(fn node ->
      for %Jido.UI.Child{kind: :region, id: id} <- node.children, do: id
    end)
    |> Enum.uniq()
  end

  defp normalize_owner(attrs) do
    key = key_for(attrs, :owner)

    case Map.fetch(attrs, key) do
      {:ok, %Jido.Agent.Ref{}} ->
        {:ok, attrs}

      {:ok, owner} ->
        with {:ok, owner} <- Jido.Agent.Ref.new(owner), do: {:ok, Map.put(attrs, key, owner)}

      :error ->
        {:ok, attrs}
    end
  end

  defp normalize_value(attrs, field, constructor) do
    key = key_for(attrs, field)

    case Map.fetch(attrs, key) do
      {:ok, value} ->
        with {:ok, value} <- constructor.(value), do: {:ok, Map.put(attrs, key, value)}

      :error ->
        {:ok, attrs}
    end
  end

  defp normalize_map(attrs, field, constructor) do
    key = key_for(attrs, field)
    values = Map.get(attrs, key, %{})

    if is_map(values) and not is_struct(values) do
      Enum.reduce_while(values, {:ok, %{}}, fn {id, value}, {:ok, result} ->
        case constructor.(value) do
          {:ok, value} -> {:cont, {:ok, Map.put(result, id, value)}}
          {:error, error} -> {:halt, {:error, Error.prepend_path(error, [field, id])}}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Map.put(attrs, key, values)}
        error -> error
      end
    else
      invalid(:invalid_region, "Region collection must be a map", %{field: field})
    end
  end

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
      {:ok, %__MODULE__{} = region} -> {:ok, region}
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid(:invalid_region, "Region is invalid", %{issues: issues})
    end
  end

  defp matching_ids(values, field) do
    case Enum.find(values, fn {id, value} -> id != value.id end) do
      nil ->
        :ok

      {id, value} ->
        invalid(:identity_mismatch, "Region key does not match value ID", %{
          field: field,
          key: id,
          id: value.id
        })
    end
  end

  defp matching_definition(region) do
    definition = region.definition
    node_ids = region.nodes |> Map.keys() |> Enum.sort()
    definition_node_ids = definition.nodes |> Map.keys() |> Enum.sort()
    action_ids = region.actions |> Map.keys() |> Enum.sort()
    intent_ids = definition.intents |> Map.keys() |> Enum.sort()

    cond do
      node_ids != definition_node_ids ->
        invalid(:projection_mismatch, "Region Nodes do not match its Definition", %{})

      action_ids != intent_ids ->
        invalid(:projection_mismatch, "Region Actions do not match its Definition", %{})

      Enum.any?(region.nodes, fn {id, node} -> not same_shape?(node, definition.nodes[id]) end) ->
        invalid(:projection_mismatch, "Bound Node changed its authored shape", %{})

      true ->
        :ok
    end
  end

  defp same_shape?(node, authored) do
    node.id == authored.id and node.component == authored.component and
      node.children == authored.children and node.events == authored.events
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
