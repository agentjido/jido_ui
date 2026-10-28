defmodule Jido.UI.Catalog.Capability do
  @moduledoc "A trusted Catalog mapping from a stable ID to an application Signal."

  alias Jido.UI.{Error, JSON}

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    event: Zoi.string() |> Zoi.min(1),
    input: Zoi.map() |> Zoi.default(%{}),
    accepts: Zoi.list(Zoi.string() |> Zoi.min(1)) |> Zoi.default([]),
    risk: Zoi.enum([:local, :normal, :guarded]) |> Zoi.default(:normal)
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Creates one trusted Capability."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = capability), do: validate(capability)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs) and not is_struct(attrs), do: parse(@attrs_schema, attrs)
  def new(value), do: invalid(value)

  @doc "Creates one Capability or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, capability} -> capability
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Capability."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = capability), do: parse(@schema, capability)
  def validate(value), do: invalid(value)

  defp parse(schema, value) do
    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = capability} -> validate_value(capability)
      {:ok, parsed} -> parsed |> then(&struct!(__MODULE__, &1)) |> validate_value()
      {:error, issues} -> invalid(issues)
    end
  end

  defp validate_value(capability) do
    with :ok <- JSON.validate(capability.input, [:input]),
         true <- Enum.uniq(capability.accepts) == capability.accepts do
      {:ok, capability}
    else
      false -> invalid(:duplicate_accepts)
      {:error, _error} = error -> error
    end
  end

  defp invalid(reason) do
    {:error, Error.new(:invalid_capability, "Capability is invalid", details: %{reason: reason})}
  end
end
