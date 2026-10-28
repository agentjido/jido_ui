defmodule Jido.UI.Surface do
  @moduledoc "A complete view composed from a topology of Agent-owned Regions."

  alias Jido.UI.{Error, JSON, Region}

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    catalog: Zoi.string() |> Zoi.min(1),
    root_region: Zoi.string() |> Zoi.min(1),
    regions: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Region)) |> Zoi.default(%{}),
    status: Zoi.enum([:ready, :busy, :waiting, :complete, :error]) |> Zoi.default(:ready),
    metadata: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Surface schema."
  def schema, do: @schema

  @doc "Creates one Surface."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = surface), do: validate(surface)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with {:ok, attrs} <- normalize_regions(attrs),
         {:ok, surface} <- parse(attrs),
         {:ok, surface} <- validate(surface) do
      {:ok, surface}
    end
  end

  def new(value), do: invalid(:invalid_surface, "Surface is invalid", %{value: value})

  @doc "Creates one Surface or raises its error."
  def new!(value) do
    case new(value) do
      {:ok, surface} -> surface
      {:error, error} -> raise error
    end
  end

  @doc "Composes one root Region and its child Region topology."
  @spec compose(String.t(), Region.t(), [Region.t()] | map(), keyword()) ::
          {:ok, t()} | {:error, Exception.t()}
  def compose(id, %Region{} = root, children \\ [], opts \\ []) do
    children = if is_map(children), do: Map.values(children), else: children
    regions = Map.new([root | children], &{&1.id, &1})

    new(%{
      id: id,
      catalog: Region.catalog(root),
      root_region: root.id,
      regions: regions,
      status: Keyword.get(opts, :status, root.status),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @doc "Composes one Surface or raises its error."
  @spec compose!(String.t(), Region.t(), [Region.t()] | map(), keyword()) :: t()
  def compose!(id, root, children \\ [], opts \\ []) do
    case compose(id, root, children, opts) do
      {:ok, surface} -> surface
      {:error, error} -> raise error
    end
  end

  @doc "Returns one Region by ID."
  @spec fetch_region(t(), String.t()) :: {:ok, Region.t()} | {:error, Error.t()}
  def fetch_region(%__MODULE__{regions: regions}, id) do
    case Map.fetch(regions, id) do
      {:ok, region} -> {:ok, region}
      :error -> invalid(:unknown_region, "Surface Region does not exist", %{region: id})
    end
  end

  @doc "Replaces one Region with a newer committed revision."
  @spec replace_region(t(), Region.t()) :: {:ok, t()} | {:error, Exception.t()}
  def replace_region(%__MODULE__{} = surface, %Region{} = region) do
    if Map.has_key?(surface.regions, region.id) do
      surface
      |> Map.put(:regions, Map.put(surface.regions, region.id, region))
      |> validate()
    else
      invalid(:unknown_region, "Surface Region does not exist", %{region: region.id})
    end
  end

  @doc "Validates Region references and topology."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = surface) do
    with {:ok, surface} <- parse(surface),
         :ok <- JSON.validate(surface.metadata, [:metadata]),
         :ok <- matching_ids(surface.regions),
         :ok <- root_exists(surface),
         :ok <- matching_catalogs(surface),
         :ok <- region_references(surface),
         :ok <- connected_region_graph(surface) do
      {:ok, surface}
    end
  end

  def validate(value), do: invalid(:invalid_surface, "Expected a Surface", %{value: value})

  defp normalize_regions(attrs) do
    key = key_for(attrs, :regions)
    values = Map.get(attrs, key, %{})

    if is_map(values) and not is_struct(values) do
      Enum.reduce_while(values, {:ok, %{}}, fn {id, value}, {:ok, result} ->
        case Region.new(value) do
          {:ok, region} -> {:cont, {:ok, Map.put(result, id, region)}}
          {:error, error} -> {:halt, {:error, Error.prepend_path(error, [:regions, id])}}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Map.put(attrs, key, values)}
        error -> error
      end
    else
      invalid(:invalid_surface, "Surface Regions must be a map", %{regions: values})
    end
  end

  defp key_for(attrs, field) do
    string = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, field) -> field
      Map.has_key?(attrs, string) -> string
      true -> field
    end
  end

  defp parse(value) do
    schema = if is_struct(value, __MODULE__), do: @schema, else: @attrs_schema

    case Zoi.parse(schema, value) do
      {:ok, %__MODULE__{} = surface} -> {:ok, surface}
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid(:invalid_surface, "Surface is invalid", %{issues: issues})
    end
  end

  defp matching_ids(regions) do
    case Enum.find(regions, fn {id, region} -> id != region.id end) do
      nil ->
        :ok

      {id, region} ->
        invalid(:identity_mismatch, "Surface key does not match Region ID", %{
          key: id,
          id: region.id
        })
    end
  end

  defp root_exists(surface) do
    if Map.has_key?(surface.regions, surface.root_region) do
      :ok
    else
      invalid(:unknown_root_region, "Surface root Region does not exist", %{
        root_region: surface.root_region
      })
    end
  end

  defp matching_catalogs(surface) do
    case Enum.find(surface.regions, fn {_id, region} ->
           Region.catalog(region) != surface.catalog
         end) do
      nil ->
        :ok

      {id, region} ->
        invalid(:catalog_mismatch, "Region uses a different Catalog", %{
          region: id,
          catalog: Region.catalog(region)
        })
    end
  end

  defp region_references(surface) do
    Enum.reduce_while(surface.regions, :ok, fn {_id, region}, :ok ->
      case Enum.find(Region.child_regions(region), &(not Map.has_key?(surface.regions, &1))) do
        nil ->
          {:cont, :ok}

        child ->
          {:halt,
           invalid(:unknown_region, "Region mounts an unknown Region", %{
             region: region.id,
             child: child
           })}
      end
    end)
  end

  defp connected_region_graph(surface) do
    case visit_region(surface.root_region, surface.regions, MapSet.new(), MapSet.new()) do
      {:ok, visited} ->
        if map_size(surface.regions) == MapSet.size(visited) do
          :ok
        else
          missing = Map.keys(surface.regions) -- MapSet.to_list(visited)
          invalid(:unreachable_region, "Surface has unreachable Regions", %{regions: missing})
        end

      error ->
        error
    end
  end

  defp visit_region(id, regions, visited, active) do
    cond do
      MapSet.member?(active, id) ->
        invalid(:region_cycle, "Surface Region graph has a cycle", %{region: id})

      MapSet.member?(visited, id) ->
        {:ok, visited}

      true ->
        active = MapSet.put(active, id)
        visited = MapSet.put(visited, id)

        regions[id]
        |> Region.child_regions()
        |> Enum.reduce_while({:ok, visited}, fn child, {:ok, result} ->
          case visit_region(child, regions, result, active) do
            {:ok, result} -> {:cont, {:ok, result}}
            error -> {:halt, error}
          end
        end)
    end
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
