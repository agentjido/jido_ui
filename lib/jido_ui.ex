defmodule Jido.UI do
  @moduledoc """
  Renderer-independent UI definitions and Agent-owned runtime surfaces.

  The authoring path is:

      DSL | Map | JSON -> Definition -> Flow -> Projection

  After the owning Agent commits its state, the application adds the trusted
  Agent reference and revision to make a Region. A Surface composes Regions.
  Renderers only receive a complete Surface.
  """

  alias Jido.UI.{Catalog, Definition, Interaction, Projection, Region, Surface}

  @doc "Validates one Surface against its trusted Catalog."
  @spec validate(Surface.t(), Catalog.t() | module()) ::
          {:ok, Surface.t()} | {:error, Exception.t()}
  def validate(surface, catalog) do
    with {:ok, catalog} <- Catalog.resolve(catalog) do
      Catalog.validate_surface(catalog, surface)
    end
  end

  @doc "Creates one canonical UI Definition."
  @spec define(Definition.t() | map() | keyword(), keyword()) ::
          {:ok, Definition.t()} | {:error, Exception.t()}
  def define(value, opts \\ []) do
    with {:ok, definition} <- Definition.new(value),
         {:ok, catalog} <- definition_catalog(definition, opts),
         {:ok, definition} <- Catalog.validate_definition(catalog, definition) do
      {:ok, definition}
    end
  end

  @doc "Creates one canonical UI Definition or raises its error."
  @spec define!(Definition.t() | map() | keyword(), keyword()) :: Definition.t()
  def define!(value, opts \\ []) do
    case define(value, opts) do
      {:ok, definition} -> definition
      {:error, error} -> raise error
    end
  end

  @doc "Projects one Definition with runtime data."
  @spec project(Definition.t() | map(), map(), keyword()) ::
          {:ok, Projection.t()} | {:error, Exception.t()}
  def project(definition, data, opts \\ []) do
    Projection.new(%{
      definition: definition,
      data: data,
      status: Keyword.get(opts, :status, :ready),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @doc "Projects one Definition or raises its error."
  @spec project!(Definition.t() | map(), map(), keyword()) :: Projection.t()
  def project!(definition, data, opts \\ []) do
    case project(definition, data, opts) do
      {:ok, projection} -> projection
      {:error, error} -> raise error
    end
  end

  @doc "Makes an Agent-owned Region from a committed Projection."
  @spec instantiate(Projection.t() | map(), keyword()) ::
          {:ok, Region.t()} | {:error, Exception.t()}
  def instantiate(projection, opts), do: Jido.UI.Region.Builder.build(projection, opts)

  @doc "Makes an Agent-owned Region or raises its error."
  @spec instantiate!(Projection.t() | map(), keyword()) :: Region.t()
  def instantiate!(projection, opts) do
    case instantiate(projection, opts) do
      {:ok, region} -> region
      {:error, error} -> raise error
    end
  end

  @doc "Creates a portable runtime-data binding."
  @spec bind(String.t()) :: map()
  def bind(path) when is_binary(path), do: %{"$path" => path}

  @doc "Routes one UI interaction to the Agent that owns its Region."
  @spec route(Interaction.t(), Surface.t(), keyword()) ::
          {:ok, Jido.Agent.Ref.t(), Jido.Signal.t()} | {:error, Exception.t()}
  defdelegate route(interaction, surface, opts \\ []), to: Interaction

  defmacro __using__(opts) do
    quote do
      use Jido.UI.DSL, unquote(opts)
    end
  end

  defp definition_catalog(definition, opts) do
    case Keyword.get(opts, :catalog) do
      nil -> Catalog.resolve(definition.catalog)
      catalog -> Catalog.resolve(catalog)
    end
  end
end
