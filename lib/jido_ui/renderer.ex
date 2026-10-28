defmodule Jido.UI.Renderer do
  @moduledoc "A behavior for renderers that consume a complete Surface."

  @callback render(Jido.UI.Surface.t(), keyword()) :: {:ok, term()} | {:error, term()}
end
