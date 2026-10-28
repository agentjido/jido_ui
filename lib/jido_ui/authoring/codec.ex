defmodule Jido.UI.Authoring.Codec do
  @moduledoc "Jido Authoring JSON codec for canonical UI Definitions."

  alias Jido.Authoring.Issue
  alias Jido.UI.{Child, Definition, Error, Intent, Node}

  @document_type "jido.ui.definition"
  @vsn 1

  @doc false
  def __jido_authoring_codec__ do
    %{type: @document_type, vsn: @vsn, encoder: Definition}
  end

  @doc false
  def encode_document(%Definition{} = definition, _registry) do
    with {:ok, definition} <- Definition.validate(definition) do
      {:ok,
       %{
         "type" => @document_type,
         "vsn" => @vsn,
         "name" => definition.name,
         "description" => definition.description,
         "definition_vsn" => definition.vsn,
         "catalog" => definition.catalog,
         "root" => definition.root,
         "nodes" => Map.new(definition.nodes, fn {id, node} -> {id, encode_node(node)} end),
         "intents" =>
           Map.new(definition.intents, fn {id, intent} -> {id, encode_intent(intent)} end),
         "metadata" => definition.metadata
       }}
    end
  end

  def encode_document(value, _registry) do
    {:error, Error.new(:invalid_definition, "Expected a Definition", details: %{value: value})}
  end

  @doc false
  def decode_document(%{"type" => @document_type, "vsn" => @vsn} = document, _registry) do
    with {:ok, nodes} <- decode_map(document["nodes"], &decode_node/1),
         {:ok, intents} <- decode_map(document["intents"] || %{}, &decode_intent/1),
         {:ok, definition} <-
           Definition.new(%{
             name: document["name"],
             description: document["description"],
             vsn: document["definition_vsn"] || 1,
             catalog: document["catalog"],
             root: document["root"],
             nodes: nodes,
             intents: intents,
             metadata: document["metadata"] || %{}
           }) do
      {:ok, definition}
    else
      {:error, %Error{} = error} -> {:error, [issue(error)]}
      {:error, [%Issue{} | _rest] = issues} -> {:error, issues}
    end
  end

  def decode_document(document, _registry) do
    {:error,
     [
       Issue.new(:invalid_document, [], "UI Definition document is invalid",
         details: %{document: document}
       )
     ]}
  end

  defp encode_node(node) do
    %{
      "id" => node.id,
      "component" => node.component,
      "props" => node.props,
      "children" => Enum.map(node.children, &%{"kind" => Atom.to_string(&1.kind), "id" => &1.id}),
      "events" => node.events
    }
  end

  defp encode_intent(intent) do
    %{"id" => intent.id, "capability" => intent.capability, "input" => intent.input}
  end

  defp decode_node(document) when is_map(document) do
    with {:ok, children} <- decode_list(document["children"] || [], &decode_child/1) do
      Node.new(%{
        id: document["id"],
        component: document["component"],
        props: document["props"] || %{},
        children: children,
        events: document["events"] || %{}
      })
    end
  end

  defp decode_node(value) do
    {:error, Error.new(:invalid_node, "Node document is invalid", details: %{value: value})}
  end

  defp decode_child(%{"kind" => "node", "id" => id}), do: Child.new(%{kind: :node, id: id})
  defp decode_child(%{"kind" => "region", "id" => id}), do: Child.new(%{kind: :region, id: id})

  defp decode_child(value) do
    {:error, Error.new(:invalid_child, "Child document is invalid", details: %{value: value})}
  end

  defp decode_intent(document) when is_map(document) do
    Intent.new(%{
      id: document["id"],
      capability: document["capability"],
      input: document["input"] || %{}
    })
  end

  defp decode_intent(value) do
    {:error, Error.new(:invalid_intent, "Intent document is invalid", details: %{value: value})}
  end

  defp decode_map(value, decoder) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {id, item}, {:ok, result} ->
      case decoder.(item) do
        {:ok, item} -> {:cont, {:ok, Map.put(result, id, item)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp decode_map(value, _decoder) do
    {:error, Error.new(:invalid_document, "Expected a document map", details: %{value: value})}
  end

  defp decode_list(values, decoder) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, result} ->
      case decoder.(value) do
        {:ok, value} -> {:cont, {:ok, [value | result]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp issue(error) do
    path = Enum.map(error.path, &to_string/1)
    Issue.new(error.code, path, error.message, details: error.details)
  end
end
