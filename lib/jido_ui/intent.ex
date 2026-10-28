defmodule Jido.UI.Intent do
  @moduledoc "An authored reference to one trusted Catalog capability."

  alias Jido.UI.{Error, JSON}

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    capability: Zoi.string() |> Zoi.min(1),
    input: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Creates one Intent."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = intent), do: validate(intent)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs) and not is_struct(attrs), do: parse(@attrs_schema, attrs)
  def new(value), do: invalid(value)

  @doc "Creates one Intent or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, intent} -> intent
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Intent."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = intent), do: parse(@schema, intent)
  def validate(value), do: invalid(value)

  defp parse(schema, value) do
    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = intent} -> validate_input(intent)
      {:ok, parsed} -> parsed |> then(&struct!(__MODULE__, &1)) |> validate_input()
      {:error, issues} -> invalid(issues)
    end
  end

  defp validate_input(intent) do
    case JSON.validate(intent.input, [:input]) do
      :ok -> {:ok, intent}
      error -> error
    end
  end

  defp invalid(reason) do
    {:error, Error.new(:invalid_intent, "Intent is invalid", details: %{reason: reason})}
  end
end
