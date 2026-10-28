defmodule Jido.UI.Renderer.Text do
  @moduledoc "A plain-text Surface renderer and fallback implementation."

  @behaviour Jido.UI.Renderer

  alias Jido.UI.{Catalog, Child, Region, Surface}
  alias Jido.UI.Catalog.Basic

  @impl true
  def render(%Surface{} = surface, opts \\ []) do
    catalog = Keyword.get(opts, :catalog, Basic.catalog())

    with {:ok, surface} <- Catalog.validate_surface(catalog, surface) do
      text = render_region(surface, surface.regions[surface.root_region])
      {:ok, String.trim(text)}
    end
  end

  defp render_region(surface, %Region{} = region) do
    render_node(surface, region, Region.root(region))
  end

  defp render_node(surface, region, node) do
    children =
      Enum.map(node.children, fn
        %Child{kind: :node, id: id} -> render_node(surface, region, region.nodes[id])
        %Child{kind: :region, id: id} -> render_region(surface, surface.regions[id])
      end)

    render_component(node.component, node.props, children)
  end

  defp render_component("stack", _props, children), do: join(children, "\n\n")
  defp render_component("action_bar", _props, children), do: join(children, " ")
  defp render_component("heading", props, _children), do: "#{heading(props)} #{props["text"]}"
  defp render_component("text", props, _children), do: props["text"]
  defp render_component("button", props, _children), do: "[#{props["label"]}]"

  defp render_component("choice_group", props, _children) do
    options = Enum.map(props["options"], &"( ) #{&1["label"]}")
    join([props["legend"] | options], "\n")
  end

  defp render_component("notice", props, _children) do
    join(Enum.reject([props["title"], props["text"]], &is_nil/1), ": ")
  end

  defp render_component("key_value", props, _children) do
    props["entries"]
    |> Enum.map(&"#{&1["label"]}: #{&1["value"]}")
    |> join("\n")
  end

  defp render_component(component, _props, children) do
    join(["[#{component}]" | children], "\n")
  end

  defp heading(props), do: String.duplicate("#", Map.get(props, "level", 2))

  defp join(values, separator) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(separator)
  end
end
