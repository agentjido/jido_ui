defmodule Jido.UI.LiveView.Theme.Bare do
  @moduledoc "A Theme that adds no presentation attributes."

  @behaviour Jido.UI.LiveView.Theme

  @impl true
  def attributes(_element, _context, _options), do: %{}
end
