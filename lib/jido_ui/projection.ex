defmodule Jido.UI.Projection do
  @moduledoc """
  A UI Definition projected with Agent state.

  A Projection is the output of a Flow. It does not contain the final Agent
  reference or revision. The application adds that boundary after commit.
  """

  alias Jido.UI.{Definition, Error, JSON}

  @fields %{
    definition: Zoi.struct(Definition),
    data: Zoi.map() |> Zoi.default(%{}),
    status: Zoi.enum([:ready, :busy, :waiting, :complete, :error]) |> Zoi.default(:ready),
    metadata: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Projection schema."
  def schema, do: @schema

  @doc "Creates one Projection."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = projection), do: validate(projection)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    key = if Map.has_key?(attrs, "definition"), do: "definition", else: :definition

    with {:ok, definition} <- Definition.new(Map.get(attrs, key)),
         {:ok, projection} <- parse(Map.put(attrs, key, definition)),
         {:ok, projection} <- validate(projection) do
      {:ok, projection}
    end
  end

  def new(value), do: invalid(value)

  @doc "Creates one Projection or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, projection} -> projection
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Projection."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = projection) do
    with {:ok, projection} <- parse(projection),
         {:ok, _definition} <- Definition.validate(projection.definition),
         :ok <- JSON.validate(projection.data, [:data]),
         :ok <- JSON.validate(projection.metadata, [:metadata]) do
      {:ok, projection}
    end
  end

  def validate(value), do: invalid(value)

  defp parse(value) do
    schema = if is_struct(value, __MODULE__), do: @schema, else: @attrs_schema

    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = projection} -> {:ok, projection}
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid(issues)
    end
  end

  defp invalid(reason) do
    {:error, Error.new(:invalid_projection, "Projection is invalid", details: %{reason: reason})}
  end
end
