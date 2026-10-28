defmodule Jido.UI.LiveView do
  @moduledoc """
  A Phoenix LiveView renderer for a complete Jido UI Surface.

  Application configuration selects the default HTML component implementation
  and Theme. A surface can replace either default and can add local Theme
  overrides. These choices do not change the Surface or its Catalog.

      config :jido_ui, Jido.UI.LiveView,
        components: MyApp.LiveComponents,
        theme: MyApp.Theme
  """

  use Phoenix.Component

  alias Jido.UI.{Catalog, Child, Region, Surface}
  alias Jido.UI.LiveView.Theme

  attr(:surface, Surface, required: true)
  attr(:components, :atom, default: nil)
  attr(:theme, :any, default: nil)
  attr(:theme_overrides, :map, default: %{})
  attr(:catalog, :atom, default: nil, doc: "Deprecated alias for components")
  attr(:target, :any, default: nil)
  attr(:id, :string, default: nil)

  @doc "Renders a Surface with the selected ComponentSet and Theme."
  def surface(assigns) do
    surface = assigns.surface
    config = Application.get_env(:jido_ui, __MODULE__, [])

    components =
      assigns.catalog || assigns.components || config[:components] || default_components()

    theme = assigns.theme || config[:theme] || default_theme()
    catalog = components.catalog()
    {:ok, surface} = Catalog.validate_surface(catalog, surface)

    content =
      render_region(
        surface,
        surface.regions[surface.root_region],
        components,
        theme,
        assigns.theme_overrides,
        assigns.target
      )

    dom_id = assigns.id || "jido-surface-#{surface.id}"

    attrs =
      Theme.merge(
        theme,
        :surface,
        %{surface: surface},
        %{
          "id" => dom_id,
          "data-jido-surface" => surface.id,
          "data-jido-surface-status" => surface.status
        },
        assigns.theme_overrides
      )

    assigns =
      assigns
      |> assign(:surface, surface)
      |> assign(:content, content)
      |> assign(:attrs, attrs)

    ~H"""
    <div {@attrs}>
      {@content}
    </div>
    """
  end

  defp default_components, do: Jido.UI.LiveView.Components.Basic
  defp default_theme, do: Jido.UI.LiveView.Theme.Bare

  defp render_region(surface, %Region{} = region, components, theme, theme_overrides, target) do
    content =
      render_node(
        surface,
        region,
        Region.root(region),
        components,
        theme,
        theme_overrides,
        target
      )

    attrs =
      Theme.merge(
        theme,
        :region,
        %{surface: surface, region: region},
        %{
          "id" => dom_id(surface, region, nil),
          "data-jido-region" => region.id,
          "data-jido-region-revision" => region.revision,
          "data-jido-agent-id" => region.owner.id
        },
        theme_overrides
      )

    assigns = %{content: content, attrs: attrs}

    ~H"""
    <section {@attrs}>
      {@content}
    </section>
    """
  end

  defp render_node(surface, region, node, components, theme, theme_overrides, target) do
    children =
      Enum.map(node.children, fn
        %Child{kind: :node, id: id} ->
          render_node(
            surface,
            region,
            region.nodes[id],
            components,
            theme,
            theme_overrides,
            target
          )

        %Child{kind: :region, id: id} ->
          render_region(
            surface,
            surface.regions[id],
            components,
            theme,
            theme_overrides,
            target
          )
      end)

    events =
      Map.new(node.events, fn {name, action_id} ->
        action = Map.fetch!(region.actions, action_id)

        {name,
         %{
           action_id: action.id,
           risk: action.risk,
           event: "jido_ui.action",
           surface_id: surface.id,
           region_id: region.id,
           region_revision: region.revision
         }}
      end)

    components.render(%{
      node: node,
      children: children,
      events: events,
      surface: surface,
      region: region,
      theme: theme,
      theme_overrides: theme_overrides,
      target: target,
      dom_id: dom_id(surface, region, node)
    })
  end

  defp dom_id(surface, region, nil), do: "#{surface.id}-region-#{region.id}"
  defp dom_id(surface, region, node), do: "#{surface.id}-#{region.id}-#{node.id}"
end
