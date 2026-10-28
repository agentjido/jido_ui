defmodule Jido.UI.Error do
  @moduledoc "A structured Jido UI validation or rendering error."

  defexception [:message, :code, path: [], details: %{}]

  @type t :: %__MODULE__{
          message: String.t(),
          code: atom(),
          path: [term()],
          details: map()
        }

  @doc false
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(code, message, opts \\ []) do
    %__MODULE__{
      code: code,
      message: message,
      path: Keyword.get(opts, :path, []),
      details: Keyword.get(opts, :details, %{})
    }
  end

  @doc false
  @spec prepend_path(t(), [term()]) :: t()
  def prepend_path(%__MODULE__{} = error, prefix) when is_list(prefix) do
    %{error | path: prefix ++ error.path}
  end
end
