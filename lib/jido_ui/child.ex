defmodule Jido.UI.Child do
  @moduledoc "A reference to one local Node or one Agent-owned Region."

  alias Jido.UI.{Error, JSON}

  @fields %{
    kind: Zoi.enum([:node, :region]),
    id: Zoi.string() |> Zoi.min(1)
  }

  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Child schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a Child. A bare string is a local Node reference."
  @spec new(t() | String.t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = child), do: validate(child)
  def new(id) when is_binary(id), do: new(%{kind: :node, id: id})
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with {:ok, attrs} <- JSON.normalize_object(attrs, Map.keys(@fields)),
         {:ok, attrs} <- normalize_kind(attrs) do
      case Zoi.parse(@attrs_schema, attrs) do
        {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
        {:error, issues} -> invalid(issues)
      end
    end
  end

  def new(value), do: invalid(value)

  @doc "Creates a Child or raises its validation error."
  @spec new!(t() | String.t() | map() | keyword()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, child} -> child
      {:error, error} -> raise error
    end
  end

  @doc "Creates a reference to a child Region."
  @spec region(String.t()) :: t()
  def region(id), do: new!(%{kind: :region, id: id})

  @doc "Validates a Child."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = child) do
    case Zoi.parse(@schema, child) do
      {:ok, child} -> {:ok, child}
      {:error, issues} -> invalid(issues)
    end
  end

  def validate(value), do: invalid(value)

  defp normalize_kind(%{kind: "node"} = attrs), do: {:ok, %{attrs | kind: :node}}
  defp normalize_kind(%{kind: "region"} = attrs), do: {:ok, %{attrs | kind: :region}}
  defp normalize_kind(attrs), do: {:ok, attrs}

  defp invalid(details) do
    {:error, Error.new(:invalid_child, "Child reference is invalid", details: %{reason: details})}
  end
end
