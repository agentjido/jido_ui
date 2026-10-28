defmodule Jido.UI.Interaction do
  @moduledoc "A user interaction with one action in an Agent-owned Region."

  alias Jido.UI.{Error, JSON, Surface}

  @fields %{
    surface_id: Zoi.string() |> Zoi.min(1),
    region_id: Zoi.string() |> Zoi.min(1),
    region_revision: Zoi.integer() |> Zoi.min(0),
    action_id: Zoi.string() |> Zoi.min(1),
    values: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Interaction schema."
  def schema, do: @schema

  @doc "Creates one Interaction."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = interaction), do: validate(interaction)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    case Zoi.parse(@attrs_schema, attrs) do
      {:ok, parsed} ->
        parsed |> then(&struct!(__MODULE__, &1)) |> validate()

      {:error, issues} ->
        invalid(:invalid_interaction, "Interaction is invalid", %{issues: issues})
    end
  end

  def new(value), do: invalid(:invalid_interaction, "Interaction is invalid", %{value: value})

  @doc "Creates one Interaction or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, interaction} -> interaction
      {:error, error} -> raise error
    end
  end

  @doc "Builds one Interaction from LiveView event parameters."
  @spec from_params(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_params(params) when is_map(params) do
    with {:ok, region_revision} <- integer_param(params, "region_revision") do
      new(%{
        surface_id: param(params, "surface_id"),
        region_id: param(params, "region_id"),
        region_revision: region_revision,
        action_id: param(params, "action_id"),
        values: Map.get(params, "values", %{})
      })
    end
  end

  def from_params(value) do
    invalid(:invalid_interaction, "Interaction parameters must be a map", %{value: value})
  end

  @doc "Validates one Interaction."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.t()}
  def validate(%__MODULE__{} = interaction) do
    with {:ok, interaction} <- parse(interaction),
         :ok <- JSON.validate(interaction.values, [:values]) do
      {:ok, interaction}
    end
  end

  def validate(value),
    do: invalid(:invalid_interaction, "Expected an Interaction", %{value: value})

  @doc "Returns the owning Agent reference and application Signal."
  @spec route(t(), Surface.t(), keyword()) ::
          {:ok, Jido.Agent.Ref.t(), Jido.Signal.t()} | {:error, Exception.t()}
  def route(%__MODULE__{} = interaction, %Surface{} = surface, opts \\ []) do
    with {:ok, interaction} <- validate(interaction),
         {:ok, surface} <- Surface.validate(surface),
         :ok <- matching_surface(interaction, surface),
         {:ok, region} <- Surface.fetch_region(surface, interaction.region_id),
         :ok <- matching_revision(interaction, region),
         {:ok, action} <- fetch_action(region, interaction.action_id),
         :ok <- accepted_values(action, interaction.values),
         input = Map.merge(action.input, interaction.values),
         {:ok, signal} <- signal(action, interaction, input, opts) do
      {:ok, region.owner, signal}
    end
  end

  defp parse(value) do
    case Zoi.parse(@schema, value) do
      {:ok, interaction} ->
        {:ok, interaction}

      {:error, issues} ->
        invalid(:invalid_interaction, "Interaction is invalid", %{issues: issues})
    end
  end

  defp param(params, name) do
    Map.get(params, name) || Map.get(params, String.replace(name, "_", "-"))
  end

  defp integer_param(params, name) do
    case param(params, name) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 ->
            {:ok, integer}

          _other ->
            invalid(:invalid_interaction, "Interaction revision is invalid", %{
              field: name,
              value: value
            })
        end

      value ->
        invalid(:invalid_interaction, "Interaction revision is invalid", %{
          field: name,
          value: value
        })
    end
  end

  defp matching_surface(interaction, surface) do
    if interaction.surface_id == surface.id do
      :ok
    else
      invalid(:surface_mismatch, "Interaction Surface ID does not match", %{
        expected: surface.id,
        actual: interaction.surface_id
      })
    end
  end

  defp matching_revision(interaction, region) do
    if interaction.region_revision == region.revision do
      :ok
    else
      invalid(:stale_region, "Interaction uses a stale Region revision", %{
        region: region.id,
        expected: region.revision,
        actual: interaction.region_revision
      })
    end
  end

  defp fetch_action(region, action_id) do
    case Map.fetch(region.actions, action_id) do
      {:ok, action} ->
        {:ok, action}

      :error ->
        invalid(:unknown_action, "Interaction Action does not exist", %{
          region: region.id,
          action: action_id
        })
    end
  end

  defp accepted_values(action, values) do
    unknown = Map.keys(values) -- action.accepts

    if unknown == [] do
      :ok
    else
      invalid(:unexpected_values, "Interaction has values that the Action does not accept", %{
        action: action.id,
        values: unknown
      })
    end
  end

  defp signal(action, interaction, input, opts) do
    data = %{
      "surface_id" => interaction.surface_id,
      "region_id" => interaction.region_id,
      "region_revision" => interaction.region_revision,
      "action_id" => interaction.action_id,
      "input" => input
    }

    signal_opts = [
      source: Keyword.get(opts, :source, "/jido-ui"),
      subject: Keyword.get(opts, :subject, "#{interaction.surface_id}/#{interaction.region_id}")
    ]

    case Jido.Signal.new(action.event, data, signal_opts) do
      {:ok, signal} ->
        {:ok, signal}

      {:error, reason} ->
        invalid(:invalid_signal, "Interaction Signal is invalid", %{reason: reason})
    end
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
