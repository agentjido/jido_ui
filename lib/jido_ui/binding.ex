defmodule Jido.UI.Binding do
  @moduledoc "Resolves portable JSON Pointer bindings against Projection data."

  alias Jido.UI.Error

  @doc "Returns true when a value contains a runtime binding."
  @spec bound?(term()) :: boolean()
  def bound?(%{"$path" => path}) when is_binary(path), do: true
  def bound?(values) when is_list(values), do: Enum.any?(values, &bound?/1)

  def bound?(value) when is_map(value) and not is_struct(value) do
    Enum.any?(value, fn {_key, item} -> bound?(item) end)
  end

  def bound?(_value), do: false

  @doc "Resolves all bindings in a value."
  @spec resolve(term(), map()) :: {:ok, term()} | {:error, Error.t()}
  def resolve(template, data) when is_map(data) and not is_struct(data) do
    resolve_value(template, data)
  end

  def resolve(_template, data) do
    {:error,
     Error.new(:invalid_binding_data, "Binding data must be a map", details: %{data: data})}
  end

  defp resolve_value(%{"$path" => path} = binding, data) when map_size(binding) == 1 do
    fetch_pointer(data, path)
  end

  defp resolve_value(values, data) when is_list(values) do
    traverse(values, &resolve_value(&1, data))
  end

  defp resolve_value(value, data) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, result} ->
      case resolve_value(item, data) do
        {:ok, item} -> {:cont, {:ok, Map.put(result, key, item)}}
        {:error, error} -> {:halt, {:error, Error.prepend_path(error, [key])}}
      end
    end)
  end

  defp resolve_value(value, _data), do: {:ok, value}

  defp fetch_pointer(data, ""), do: {:ok, data}

  defp fetch_pointer(data, "/" <> pointer) do
    pointer
    |> String.split("/", trim: false)
    |> Enum.map(&unescape/1)
    |> Enum.reduce_while({:ok, data}, fn part, {:ok, current} ->
      case fetch_part(current, part) do
        {:ok, value} -> {:cont, {:ok, value}}
        :error -> {:halt, binding_error("/" <> pointer)}
      end
    end)
  end

  defp fetch_pointer(_data, path), do: binding_error(path)

  defp fetch_part(value, key) when is_map(value), do: Map.fetch(value, key)

  defp fetch_part(value, key) when is_list(value) do
    case Integer.parse(key) do
      {index, ""} when index >= 0 -> Enum.fetch(value, index)
      _other -> :error
    end
  end

  defp fetch_part(_value, _key), do: :error

  defp unescape(value), do: value |> String.replace("~1", "/") |> String.replace("~0", "~")

  defp traverse(values, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, result} ->
      case mapper.(value) do
        {:ok, value} -> {:cont, {:ok, [value | result]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp binding_error(path) do
    {:error, Error.new(:invalid_binding, "Binding path does not exist", details: %{path: path})}
  end
end
