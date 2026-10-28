defmodule Jido.UI.LiveView.Components.Basic do
  @moduledoc """
  Accessible HTML markup for `Jido.UI.Catalog.Basic`.

  The component set owns markup and interaction attributes. The selected
  `Jido.UI.LiveView.Theme` owns presentation classes and theme attributes.
  """

  use Phoenix.Component

  @behaviour Jido.UI.LiveView.ComponentSet

  alias Jido.UI.LiveView.Theme

  @impl true
  def catalog, do: Jido.UI.Catalog.Basic.catalog()

  @impl true
  def render(%{node: %{component: "stack"}} = assigns) do
    assigns = themed(assigns, "stack", %{"id" => assigns.dom_id})

    ~H"""
    <div {@attrs} data-jido-component="stack" data-gap={@node.props["gap"] || "medium"}>
      <%= for child <- @children do %>
        {child}
      <% end %>
    </div>
    """
  end

  def render(%{node: %{component: "action_bar"}} = assigns) do
    assigns = themed(assigns, "action_bar", %{"id" => assigns.dom_id})

    ~H"""
    <div {@attrs} data-jido-component="action-bar" role="group">
      <%= for child <- @children do %>
        {child}
      <% end %>
    </div>
    """
  end

  def render(%{node: %{component: "heading"}} = assigns) do
    assigns =
      assigns
      |> themed("heading", %{"id" => assigns.dom_id})
      |> Map.put(:tag, "h#{assigns.node.props["level"] || 2}")

    ~H"""
    <.dynamic_tag tag_name={@tag} {@attrs} data-jido-component="heading">
      {@node.props["text"]}
    </.dynamic_tag>
    """
  end

  def render(%{node: %{component: "text"}} = assigns) do
    assigns = themed(assigns, "text", %{"id" => assigns.dom_id})

    ~H"""
    <p {@attrs} data-jido-component="text" data-tone={@node.props["tone"] || "default"}>
      {@node.props["text"]}
    </p>
    """
  end

  def render(%{node: %{component: "button"}} = assigns) do
    action = assigns.events["activate"]

    protected = %{
      "id" => assigns.dom_id,
      "type" => "button",
      "phx-click" => action && action.event,
      "phx-target" => assigns.target,
      "phx-value-surface-id" => action && action.surface_id,
      "phx-value-region-id" => action && action.region_id,
      "phx-value-region-revision" => action && action.region_revision,
      "phx-value-action-id" => action && action.action_id
    }

    assigns =
      assigns
      |> Map.put(:action, action)
      |> themed("button", protected)

    ~H"""
    <button
      {@attrs}
      data-jido-component="button"
      data-variant={@node.props["variant"] || "secondary"}
      data-risk={@action && @action.risk}
    >
      {@node.props["label"]}
    </button>
    """
  end

  def render(%{node: %{component: "choice_group"}} = assigns) do
    assigns = themed(assigns, "choice_group", %{"id" => assigns.dom_id})

    ~H"""
    <fieldset {@attrs} data-jido-component="choice-group">
      <legend>{@node.props["legend"]}</legend>
      <%= for option <- @node.props["options"] do %>
        <label>
          <input type="radio" name={@node.props["name"]} value={option["value"]} />
          {option["label"]}
        </label>
      <% end %>
    </fieldset>
    """
  end

  def render(%{node: %{component: "notice"}} = assigns) do
    protected = %{
      "id" => assigns.dom_id,
      "role" => notice_role(assigns.node.props["tone"])
    }

    assigns = themed(assigns, "notice", protected)

    ~H"""
    <aside
      {@attrs}
      data-jido-component="notice"
      data-tone={@node.props["tone"] || "default"}
    >
      <strong :if={@node.props["title"]}>{@node.props["title"]}</strong>
      <p>{@node.props["text"]}</p>
    </aside>
    """
  end

  def render(%{node: %{component: "key_value"}} = assigns) do
    assigns = themed(assigns, "key_value", %{"id" => assigns.dom_id})

    ~H"""
    <dl {@attrs} data-jido-component="key-value">
      <%= for entry <- @node.props["entries"] do %>
        <div>
          <dt>{entry["label"]}</dt>
          <dd>{entry["value"]}</dd>
        </div>
      <% end %>
    </dl>
    """
  end

  defp themed(assigns, element, protected) do
    attrs =
      Theme.merge(
        assigns.theme,
        element,
        assigns,
        protected,
        Map.get(assigns, :theme_overrides, %{})
      )

    Map.put(assigns, :attrs, attrs)
  end

  defp notice_role(tone) when tone in ["danger", "warning"], do: "alert"
  defp notice_role(_tone), do: "status"
end
