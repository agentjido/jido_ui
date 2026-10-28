defmodule Jido.UI.JSON do
  @moduledoc false

  alias Jido.UI.Error

  @spec validate(term(), [term()]) :: :ok | {:error, Error.t()}
  def validate(value, path \\ [])

  def validate(value, _path)
      when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
      do: :ok

  def validate(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case validate(value, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  def validate(value, path) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, :ok, fn
      {key, item}, :ok when is_binary(key) ->
        case validate(item, path ++ [key]) do
          :ok -> {:cont, :ok}
          {:error, _error} = error -> {:halt, error}
        end

      {key, _item}, :ok ->
        {:halt,
         {:error,
          Error.new(:nonportable_data, "Portable UI maps require string keys",
            path: path ++ [key],
            details: %{key: key}
          )}}
    end)
  end

  def validate(value, path) do
    {:error,
     Error.new(:nonportable_data, "UI data contains a nonportable value",
       path: path,
       details: %{value: inspect(value)}
     )}
  end
end
