defmodule Jido.UI.DSL.Helpers do
  @moduledoc false

  @doc "Creates a runtime-data binding for Node properties or Intent input."
  def bind(path), do: Jido.UI.bind(path)

  @doc "Creates a child Region mount."
  def region(id), do: Jido.UI.Child.region(id)
end
