defmodule Jido.UI.Catalog do
  @moduledoc """
  A trusted set of component schemas and interaction capabilities.

  Authored Definitions use stable capability IDs. Only a server-owned Catalog
  maps those IDs to application Signal types.
  """

  alias Jido.UI.{Binding, Definition, Error, Region}
  alias Jido.UI.Catalog.Capability

  @enforce_keys [:id, :components, :capabilities]
  defstruct [:id, :components, :capabilities]

  @type t :: %__MODULE__{
          id: String.t(),
          components: %{required(String.t()) => Zoi.schema()},
          capabilities: %{required(String.t()) => Capability.t()}
        }

  @doc "Creates one trusted Catalog."
  @spec new(String.t(), map(), map()) :: {:ok, t()} | {:error, Error.t()}
  def new(id, components, capabilities \\ %{})

  def new(id, components, capabilities)
      when is_binary(id) and byte_size(id) > 0 and is_map(components) and
             not is_struct(components) and is_map(capabilities) and not is_struct(capabilities) do
    with :ok <- component_names(components),
         {:ok, capabilities} <- normalize_capabilities(capabilities) do
      {:ok, %__MODULE__{id: id, components: components, capabilities: capabilities}}
    end
  end

  def new(id, components, capabilities) do
    invalid(:invalid_catalog, "Catalog fields are invalid", %{
      id: id,
      components: components,
      capabilities: capabilities
    })
  end

  @doc "Creates one Catalog or raises its error."
  @spec new!(String.t(), map(), map()) :: t()
  def new!(id, components, capabilities \\ %{}) do
    case new(id, components, capabilities) do
      {:ok, catalog} -> catalog
      {:error, error} -> raise error
    end
  end

  @doc "Resolves a Catalog value, module, or built-in ID."
  @spec resolve(t() | module() | String.t()) :: {:ok, t()} | {:error, Error.t()}
  def resolve(%__MODULE__{} = catalog), do: {:ok, catalog}

  def resolve(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :catalog, 0) do
      resolve(module.catalog())
    else
      invalid(:unknown_catalog, "Catalog module does not export catalog/0", %{catalog: module})
    end
  end

  def resolve(id) when is_binary(id) do
    catalog = Jido.UI.Catalog.Basic.catalog()

    if catalog.id == id do
      {:ok, catalog}
    else
      invalid(:unknown_catalog, "Catalog ID is not registered", %{catalog: id})
    end
  end

  def resolve(value), do: invalid(:invalid_catalog, "Catalog value is invalid", %{catalog: value})

  @doc "Returns one trusted capability."
  @spec fetch_capability(t(), String.t()) :: {:ok, Capability.t()} | {:error, Error.t()}
  def fetch_capability(%__MODULE__{} = catalog, id) do
    case Map.fetch(catalog.capabilities, id) do
      {:ok, capability} ->
        {:ok, capability}

      :error ->
        invalid(:unknown_capability, "Capability is not in the Catalog", %{capability: id})
    end
  end

  @doc "Validates authored references and literal component properties."
  @spec validate_definition(t(), Definition.t()) ::
          {:ok, Definition.t()} | {:error, Error.t()}
  def validate_definition(%__MODULE__{} = catalog, %Definition{} = definition) do
    with :ok <- matching_catalog(catalog, definition.catalog),
         :ok <- validate_definition_nodes(catalog, definition),
         :ok <- validate_intents(catalog, definition) do
      {:ok, definition}
    end
  end

  @doc "Validates all bound component properties in one runtime Region."
  @spec validate_region(t(), Region.t()) :: {:ok, Region.t()} | {:error, Error.t()}
  def validate_region(%__MODULE__{} = catalog, %Region{} = region) do
    with :ok <- matching_catalog(catalog, region.definition.catalog),
         :ok <- validate_runtime_nodes(catalog, region) do
      {:ok, region}
    end
  end

  @doc "Validates every Region in one complete Surface."
  @spec validate_surface(t(), Jido.UI.Surface.t()) ::
          {:ok, Jido.UI.Surface.t()} | {:error, Exception.t()}
  def validate_surface(%__MODULE__{} = catalog, %Jido.UI.Surface{} = surface) do
    with {:ok, surface} <- Jido.UI.Surface.validate(surface),
         :ok <- matching_catalog(catalog, surface.catalog),
         :ok <- validate_surface_regions(catalog, surface) do
      {:ok, surface}
    end
  end

  defp component_names(components) do
    case Enum.find(components, fn {name, _schema} -> not is_binary(name) or name == "" end) do
      nil -> :ok
      {name, _schema} -> invalid(:invalid_catalog, "Component name is invalid", %{name: name})
    end
  end

  defp normalize_capabilities(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn {id, value}, {:ok, result} ->
      value =
        if is_map(value) and not is_struct(value), do: Map.put_new(value, :id, id), else: value

      case Capability.new(value) do
        {:ok, %{id: ^id} = capability} ->
          {:cont, {:ok, Map.put(result, id, capability)}}

        {:ok, capability} ->
          {:halt,
           invalid(:identity_mismatch, "Capability key does not match its ID", %{
             key: id,
             id: capability.id
           })}

        {:error, error} ->
          {:halt, {:error, Error.prepend_path(error, [:capabilities, id])}}
      end
    end)
  end

  defp matching_catalog(%__MODULE__{id: id}, id), do: :ok

  defp matching_catalog(catalog, actual) do
    invalid(:catalog_mismatch, "Definition Catalog ID does not match the Catalog", %{
      expected: catalog.id,
      actual: actual
    })
  end

  defp validate_definition_nodes(catalog, definition) do
    Enum.reduce_while(definition.nodes, :ok, fn {_id, node}, :ok ->
      case Map.fetch(catalog.components, node.component) do
        {:ok, schema} ->
          if Binding.bound?(node.props) do
            {:cont, :ok}
          else
            validation_result(schema, node.props, node.id, node.component)
          end

        :error ->
          {:halt,
           invalid(:unknown_component, "Node component is not in the Catalog", %{
             node: node.id,
             component: node.component
           })}
      end
    end)
  end

  defp validate_intents(catalog, definition) do
    Enum.reduce_while(definition.intents, :ok, fn {_id, intent}, :ok ->
      case fetch_capability(catalog, intent.capability) do
        {:ok, _capability} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, Error.prepend_path(error, [:intents, intent.id])}}
      end
    end)
  end

  defp validate_runtime_nodes(catalog, region) do
    Enum.reduce_while(region.nodes, :ok, fn {_id, node}, :ok ->
      case Map.fetch(catalog.components, node.component) do
        {:ok, schema} ->
          validation_result(schema, node.props, node.id, node.component)

        :error ->
          {:halt,
           invalid(:unknown_component, "Node component is not in the Catalog", %{
             region: region.id,
             node: node.id,
             component: node.component
           })}
      end
    end)
  end

  defp validate_surface_regions(catalog, surface) do
    Enum.reduce_while(surface.regions, :ok, fn {_id, region}, :ok ->
      case validate_region(catalog, region) do
        {:ok, _region} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validation_result(schema, props, node, component) do
    case Zoi.parse(schema, props) do
      {:ok, _props} ->
        {:cont, :ok}

      {:error, issues} ->
        {:halt,
         invalid(:invalid_component_props, "Node properties do not match the Catalog", %{
           node: node,
           component: component,
           issues: issues
         })}
    end
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
