defmodule JidoUI.Examples.Lifecycle.Catalog do
  @moduledoc false

  alias Jido.UI.Catalog
  alias Jido.UI.Catalog.{Basic, Capability}

  def catalog do
    basic = Basic.catalog()

    capabilities = %{
      "tea.advance" =>
        Capability.new!(%{
          id: "tea.advance",
          event: "tea.advance",
          risk: :normal
        })
    }

    Catalog.new!(basic.id, basic.components, capabilities)
  end
end
