defmodule Jido.UI.LiveView.Theme do
  @moduledoc """
  Presentation attributes for LiveView surfaces and components.

  Themes are trusted modules. They do not change the renderer-independent
  Catalog, Node properties, component markup, or interaction routing.

  Select a Theme module directly or use `{module, options}`:

      Jido.UI.LiveView.Theme.Bare
      {Jido.UI.LiveView.Theme.DaisyUI, name: "cupcake"}

  A renderer has one global Theme selection. The renderer can add local
  presentation attributes with an override map:

      %{
        surface: %{"class" => "compact"},
        regions: %{"brew" => %{"class" => "warm"}},
        components: %{"button" => %{"class" => "rounded"}},
        nodes: %{"brew" => %{"refresh" => %{"class" => "quiet"}}}
      }

  Classes from all applicable layers are combined. Other attributes use the
  most local value. Renderer-owned attributes are applied last.
  """

  alias Jido.UI.Error

  @type element :: :surface | :region | String.t()
  @type context :: map()
  @type selection :: module() | {module(), keyword()}
  @type attributes :: %{optional(String.t() | atom()) => term()}
  @type overrides :: map()

  @callback attributes(element(), context(), keyword()) :: attributes()

  @doc "Returns validated attributes for one rendered element."
  @spec attributes(selection(), element(), context()) :: attributes()
  def attributes(selection, element, context) when is_map(context) do
    {module, options} = split(selection)

    unless Code.ensure_loaded?(module) and function_exported?(module, :attributes, 3) do
      raise Error.new(:invalid_theme, "LiveView Theme does not implement attributes/3",
              details: %{theme: module}
            )
    end

    case module.attributes(element, context, options) do
      attributes when is_map(attributes) and not is_struct(attributes) ->
        normalize(attributes)

      value ->
        raise Error.new(:invalid_theme, "LiveView Theme returned invalid attributes",
                details: %{theme: module, value: value}
              )
    end
  end

  @doc "Merges Theme attributes with protected renderer attributes."
  @spec merge(selection(), element(), context(), attributes()) :: attributes()
  def merge(selection, element, context, protected) when is_map(protected) do
    merge(selection, element, context, protected, %{})
  end

  @doc "Merges global Theme, local overrides, and protected renderer attributes."
  @spec merge(selection(), element(), context(), attributes(), overrides()) :: attributes()
  def merge(selection, element, context, protected, overrides)
      when is_map(protected) and is_map(overrides) do
    layers =
      [attributes(selection, element, context)] ++
        override_layers(overrides, element, context) ++ [protected]

    merge_layers(layers)
  end

  defp override_layers(overrides, :surface, _context) do
    [validate_override([:surface], override(overrides, :surface, %{}))]
  end

  defp override_layers(overrides, :region, %{region: region}) do
    [nested_override(overrides, [:regions, region.id])]
  end

  defp override_layers(overrides, element, %{region: region, node: node})
       when is_binary(element) do
    [
      nested_override(overrides, [:components, element]),
      nested_override(overrides, [:nodes, region.id, node.id])
    ]
  end

  defp override_layers(_overrides, _element, _context), do: []

  defp nested_override(overrides, path) do
    Enum.reduce_while(path, overrides, fn key, current ->
      case override(current, key, :missing) do
        :missing -> {:halt, %{}}
        value when is_map(value) -> {:cont, value}
        value -> invalid_override(path, value)
      end
    end)
  end

  defp override(overrides, key, default) do
    Map.get(overrides, key, Map.get(overrides, to_string(key), default))
  end

  defp invalid_override(path, value) do
    raise Error.new(:invalid_theme, "LiveView Theme override must be a map",
            details: %{path: path, value: value}
          )
  end

  defp validate_override(_path, value) when is_map(value), do: value
  defp validate_override(path, value), do: invalid_override(path, value)

  defp merge_layers(layers) do
    layers = Enum.map(layers, &normalize/1)
    classes = layers |> Enum.map(&Map.get(&1, "class")) |> merge_classes()

    layers
    |> Enum.reduce(%{}, fn layer, merged -> Map.merge(merged, layer) end)
    |> put_classes(classes)
  end

  defp split({module, options}) when is_atom(module) and is_list(options), do: {module, options}
  defp split(module) when is_atom(module), do: {module, []}

  defp split(value) do
    raise Error.new(:invalid_theme, "LiveView Theme selection is invalid",
            details: %{theme: value}
          )
  end

  defp normalize(attributes) do
    Map.new(attributes, fn {key, value} -> {to_string(key), value} end)
  end

  defp merge_classes(values) do
    values
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp put_classes(attributes, ""), do: Map.delete(attributes, "class")
  defp put_classes(attributes, classes), do: Map.put(attributes, "class", classes)
end
