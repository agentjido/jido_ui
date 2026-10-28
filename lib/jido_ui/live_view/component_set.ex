defmodule Jido.UI.LiveView.ComponentSet do
  @moduledoc """
  A LiveView markup implementation for one renderer-independent Catalog.

  A ComponentSet decides which HTML elements implement semantic components.
  A Theme supplies presentation attributes to that markup.
  """

  @type assigns :: %{
          required(:node) => Jido.UI.Node.t(),
          required(:children) => [Phoenix.LiveView.Rendered.t()],
          required(:events) => map(),
          required(:surface) => Jido.UI.Surface.t(),
          required(:region) => Jido.UI.Region.t(),
          required(:theme) => Jido.UI.LiveView.Theme.selection(),
          required(:target) => term(),
          required(:dom_id) => String.t()
        }

  @callback catalog() :: Jido.UI.Catalog.t()
  @callback render(assigns()) :: Phoenix.LiveView.Rendered.t()
end
