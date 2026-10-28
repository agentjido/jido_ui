defmodule Jido.UI.Region.Action do
  @moduledoc "A resolved Intent that maps one Region interaction to a Signal type."

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

  @doc "Returns the Action schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates and validates one Action."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = action), do: validate(action)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    case Zoi.parse(@attrs_schema, attrs) do
      {:ok, parsed} -> parsed |> then(&struct!(__MODULE__, &1)) |> validate()
      {:error, issues} -> invalid(issues)
    end
  end

  def new(value), do: invalid(value)

  @doc "Creates one Action or raises its validation error."
  @spec new!(t() | map() | keyword()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, action} -> action
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Action and its portable input template."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = action) do
    with {:ok, action} <- parse(action),
         :ok <- JSON.validate(action.input, [:input]),
         :ok <- unique_accepts(action.accepts) do
      {:ok, action}
    end
  end

  def validate(value), do: invalid(value)

  defp parse(action) do
    case Zoi.parse(@schema, action) do
      {:ok, action} -> {:ok, action}
      {:error, issues} -> invalid(issues)
    end
  end

  defp unique_accepts(values) do
    if Enum.uniq(values) == values do
      :ok
    else
      {:error,
       Error.new(:invalid_action, "Action accepts must contain unique names",
         path: [:accepts],
         details: %{accepts: values}
       )}
    end
  end

  defp invalid(details) do
    {:error, Error.new(:invalid_action, "Action is invalid", details: %{reason: details})}
  end
end
