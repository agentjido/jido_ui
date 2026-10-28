defmodule Jido.UI.DSL do
  @moduledoc false

  use Spark.Dsl,
    default_extensions: [extensions: [Jido.UI.DSL.Extension]],
    opt_schema: [
      id: [type: :string],
      name: [type: :string, required: true],
      description: [type: :string],
      vsn: [type: :pos_integer, default: 1],
      catalog: [type: :atom, required: true],
      metadata: [type: :any]
    ]

  @impl true
  def handle_before_compile(opts) do
    quote do
      {definition, catalog} =
        Jido.UI.DSL.Compiler.compile!(
          @spark_dsl_config,
          unquote(Macro.escape(opts)),
          __MODULE__
        )

      @jido_ui_definition definition
      @jido_ui_catalog catalog

      @doc "Returns the canonical UI Definition."
      @spec definition() :: Jido.UI.Definition.t()
      def definition, do: @jido_ui_definition

      @doc "Returns the trusted component and capability Catalog."
      @spec catalog() :: Jido.UI.Catalog.t()
      def catalog, do: @jido_ui_catalog

      @doc "Projects runtime data with this Definition."
      @spec project(map(), keyword()) ::
              {:ok, Jido.UI.Projection.t()} | {:error, Exception.t()}
      def project(data, options \\ []), do: Jido.UI.project(definition(), data, options)

      @doc "Makes an Agent-owned Region from one Projection."
      @spec instantiate(Jido.UI.Projection.t(), keyword()) ::
              {:ok, Jido.UI.Region.t()} | {:error, Exception.t()}
      def instantiate(projection, options) do
        Jido.UI.instantiate(projection, Keyword.put_new(options, :catalog, catalog()))
      end

      @doc false
      def __jido_authoring_kind__, do: :ui_definition

      @doc false
      def __jido_authoring__ do
        %{
          id: unquote(opts[:id] || opts[:name]),
          kind: :ui_definition,
          vsn: @jido_ui_definition.vsn,
          target: @jido_ui_definition,
          name: @jido_ui_definition.name,
          description: @jido_ui_definition.description
        }
      end
    end
  end
end
