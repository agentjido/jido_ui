defmodule Jido.UI.Region.Builder do
  @moduledoc false

  alias Jido.UI.{Binding, Catalog, Projection, Region}

  @spec build(Projection.t() | map(), keyword()) ::
          {:ok, Region.t()} | {:error, Exception.t()}
  def build(projection, opts) when is_list(opts) do
    with {:ok, projection} <- Projection.new(projection),
         {:ok, owner} <- fetch_option(opts, :owner),
         {:ok, revision} <- fetch_option(opts, :revision),
         {:ok, catalog} <- projection_catalog(projection, opts),
         {:ok, nodes} <- bind_nodes(projection),
         {:ok, actions} <- resolve_actions(projection, catalog),
         {:ok, region} <-
           Region.new(%{
             id: Keyword.get(opts, :id, projection.definition.name),
             owner: owner,
             revision: revision,
             definition: projection.definition,
             nodes: nodes,
             data: projection.data,
             actions: actions,
             status: projection.status,
             metadata: projection.metadata
           }),
         {:ok, region} <- Catalog.validate_region(catalog, region) do
      {:ok, region}
    end
  end

  defp bind_nodes(projection) do
    projection.definition.nodes
    |> Enum.reduce_while({:ok, %{}}, fn {id, node}, {:ok, nodes} ->
      case Binding.resolve(node.props, projection.data) do
        {:ok, props} -> {:cont, {:ok, Map.put(nodes, id, %{node | props: props})}}
        {:error, error} -> {:halt, {:error, Jido.UI.Error.prepend_path(error, [:nodes, id])}}
      end
    end)
  end

  defp resolve_actions(projection, catalog) do
    projection.definition.intents
    |> Enum.reduce_while({:ok, %{}}, fn {id, intent}, {:ok, actions} ->
      with {:ok, capability} <- Catalog.fetch_capability(catalog, intent.capability),
           {:ok, input} <- Binding.resolve(intent.input, projection.data),
           input = Map.merge(capability.input, input),
           {:ok, action} <-
             Jido.UI.Region.Action.new(%{
               id: id,
               event: capability.event,
               input: input,
               accepts: capability.accepts,
               risk: capability.risk
             }) do
        {:cont, {:ok, Map.put(actions, id, action)}}
      else
        {:error, error} ->
          {:halt, {:error, Jido.UI.Error.prepend_path(error, [:intents, id])}}
      end
    end)
  end

  defp projection_catalog(projection, opts) do
    case Keyword.get(opts, :catalog) do
      nil -> Catalog.resolve(projection.definition.catalog)
      catalog -> Catalog.resolve(catalog)
    end
  end

  defp fetch_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error,
         Jido.UI.Error.new(:missing_runtime_boundary, "Region runtime boundary is incomplete",
           path: [key]
         )}
    end
  end
end
