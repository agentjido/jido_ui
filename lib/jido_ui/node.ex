defmodule Jido.UI.Node do
  @moduledoc "One catalog component in an Agent-owned Region."

  alias Jido.UI.{Child, Error, JSON}

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    component: Zoi.string() |> Zoi.min(1),
    props: Zoi.map() |> Zoi.default(%{}),
    children: Zoi.list(Zoi.struct(Child)) |> Zoi.default([]),
    events:
      Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.string() |> Zoi.min(1))
      |> Zoi.default(%{})
  }

  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Node schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates and validates one Node. Bare child strings refer to local Nodes."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = node), do: validate(node)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with {:ok, attrs} <- JSON.normalize_object(attrs, Map.keys(@fields)),
         {:ok, attrs} <- normalize_children(attrs),
         {:ok, node} <- parse(attrs),
         {:ok, node} <- validate(node) do
      {:ok, node}
    end
  end

  def new(value), do: invalid(value)

  @doc "Creates one Node or raises its validation error."
  @spec new!(t() | map() | keyword()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, node} -> node
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Node and its portable properties."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = node) do
    with {:ok, node} <- parse(node),
         :ok <- JSON.validate(node.props, [:props]) do
      {:ok, node}
    end
  end

  def validate(value), do: invalid(value)

  defp normalize_children(attrs) do
    key =
      cond do
        Map.has_key?(attrs, :children) -> :children
        Map.has_key?(attrs, "children") -> "children"
        true -> :children
      end

    children = Map.get(attrs, key, [])

    if is_list(children) do
      Enum.reduce_while(children, {:ok, []}, fn child, {:ok, acc} ->
        case Child.new(child) do
          {:ok, child} -> {:cont, {:ok, [child | acc]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, normalized} -> {:ok, Map.put(attrs, key, Enum.reverse(normalized))}
        {:error, _error} = error -> error
      end
    else
      invalid(children)
    end
  end

  defp parse(value) do
    schema = if is_struct(value, __MODULE__), do: @schema, else: @attrs_schema

    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = node} -> {:ok, node}
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid(issues)
    end
  end

  defp invalid(details) do
    {:error, Error.new(:invalid_node, "Node is invalid", details: %{reason: details})}
  end
end
