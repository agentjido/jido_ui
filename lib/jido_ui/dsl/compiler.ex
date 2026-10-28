defmodule Jido.UI.DSL.Compiler do
  @moduledoc false

  alias Jido.UI.DSL.{Intent, Node}
  alias Spark.Dsl.Extension

  @doc false
  @spec compile!(map(), keyword(), module()) :: {Jido.UI.Definition.t(), Jido.UI.Catalog.t()}
  def compile!(dsl, opts, module) do
    with {:ok, catalog} <- Jido.UI.Catalog.resolve(opts[:catalog]),
         {:ok, definition} <- Jido.UI.define(attributes(dsl, opts, catalog), catalog: catalog) do
      {definition, catalog}
    else
      {:error, error} ->
        raise Spark.Error.DslError,
          module: module,
          path: [:ui | Map.get(error, :path, [])],
          message: Exception.message(error)
    end
  end

  defp attributes(dsl, opts, catalog) do
    entities = Extension.get_entities(dsl, [:ui])

    %{
      name: opts[:name],
      description: opts[:description],
      vsn: opts[:vsn],
      catalog: catalog.id,
      root: Extension.get_opt(dsl, [:ui], :root),
      nodes: entities |> Enum.filter(&is_struct(&1, Node)) |> Map.new(&lower_node/1),
      intents: entities |> Enum.filter(&is_struct(&1, Intent)) |> Map.new(&lower_intent/1),
      metadata: opts[:metadata] || %{}
    }
  end

  defp lower_node(node) do
    {node.id,
     %{
       id: node.id,
       component: node.component,
       props: node.props,
       children: node.children,
       events: node.events
     }}
  end

  defp lower_intent(intent) do
    {intent.id,
     %{
       id: intent.id,
       capability: intent.capability,
       input: intent.input
     }}
  end
end
