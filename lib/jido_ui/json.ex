defmodule Jido.UI.JSON do
  @moduledoc false

  alias Jido.UI.Error

  @doc false
  @spec portable(term()) :: term()
  def portable(value)

  def portable(value)
      when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
      do: value

  def portable(value) when is_atom(value), do: Atom.to_string(value)
  def portable(values) when is_list(values), do: Enum.map(values, &portable/1)

  def portable(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, item} -> {to_string(key), portable(item)} end)
  end

  def portable(value), do: value

  @doc false
  @spec encode_canonical(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode_canonical(value) do
    with :ok <- validate(value) do
      case value |> canonical() |> Jason.encode() do
        {:ok, json} -> {:ok, json}
        {:error, error} -> invalid(:json_encode_failed, "UI data could not be encoded", error)
      end
    end
  end

  @doc false
  @spec digest(term()) :: {:ok, binary()} | {:error, Error.t()}
  def digest(value) do
    with {:ok, json} <- encode_canonical(value) do
      digest = json |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
      {:ok, digest}
    end
  end

  @doc false
  @spec normalize_object(map(), [atom()]) :: {:ok, map()} | {:error, Error.t()}
  def normalize_object(value, fields) when is_map(value) and is_list(fields) do
    Enum.reduce_while(fields, {:ok, value}, fn field, {:ok, result} ->
      string = Atom.to_string(field)

      case {Map.fetch(result, field), Map.fetch(result, string)} do
        {{:ok, _atom_value}, {:ok, _string_value}} ->
          {:halt,
           {:error,
            Error.new(:duplicate_field, "UI object has the same field more than once",
              path: [string],
              details: %{field: string}
            )}}

        {:error, {:ok, string_value}} ->
          {:cont, {:ok, result |> Map.delete(string) |> Map.put(field, string_value)}}

        _other ->
          {:cont, {:ok, result}}
      end
    end)
  end

  @spec validate(term(), [term()]) :: :ok | {:error, Error.t()}
  def validate(value, path \\ [])

  def validate(value, _path)
      when is_nil(value) or is_boolean(value) or is_number(value),
      do: :ok

  def validate(value, path) when is_binary(value) do
    if String.valid?(value) do
      :ok
    else
      {:error,
       Error.new(:nonportable_data, "UI strings must contain valid UTF-8",
         path: path,
         details: %{value: inspect(value)}
       )}
    end
  end

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

  defp canonical(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.sort_by(fn {key, _item} -> key end)
    |> Enum.map(fn {key, item} -> {key, canonical(item)} end)
    |> Jason.OrderedObject.new()
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp invalid(code, message, value) do
    {:error, Error.new(code, message, details: %{value: inspect(value)})}
  end
end
