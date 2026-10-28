defmodule Jido.UI.Release do
  @moduledoc """
  An immutable, content-verified UI Definition artifact.

  A Release is the runtime form of a Builder draft. It keeps the canonical
  Jido Authoring document, the exact Catalog identity, and the source data
  needed to explain the build. `encode/1` is the durable database boundary.
  """

  alias Jido.UI.{Authoring.Codec, Catalog, Definition, Error, JSON}

  @document_type "jido.ui.release"
  @document_vsn 1
  @wire_keys ~w(
    type vsn id digest application_id build_id catalog catalog_digest
    definition_version document source metadata
  )
  @digest_schema Zoi.string() |> Zoi.regex(~r/\A[0-9a-f]{64}\z/)

  @fields %{
    id: Zoi.string() |> Zoi.min(1),
    digest: @digest_schema,
    application_id: Zoi.string() |> Zoi.min(1),
    build_id: Zoi.string() |> Zoi.min(1),
    catalog: Zoi.string() |> Zoi.min(1),
    catalog_digest: @digest_schema,
    definition_version: Zoi.integer() |> Zoi.min(1),
    document: Zoi.map(),
    source: Zoi.map() |> Zoi.default(%{}),
    metadata: Zoi.map() |> Zoi.default(%{})
  }
  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Release schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Freezes one validated Definition as an immutable Release."
  @spec freeze(Definition.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def freeze(%Definition{} = definition, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      freeze_definition(definition, opts)
    else
      invalid(:invalid_options, "Release options must be a keyword list", %{options: opts})
    end
  end

  def freeze(%Definition{}, opts) do
    invalid(:invalid_options, "Release options must be a keyword list", %{options: opts})
  end

  def freeze(value, _opts) do
    invalid(:invalid_release_definition, "Release requires a UI Definition", %{value: value})
  end

  @doc "Creates and verifies one Release."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = release), do: validate(release)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    case Zoi.parse(@attrs_schema, attrs) do
      {:ok, parsed} -> parsed |> then(&struct!(__MODULE__, &1)) |> validate()
      {:error, issues} -> invalid(:invalid_release, "Release is invalid", %{issues: issues})
    end
  end

  def new(value), do: invalid(:invalid_release, "Release is invalid", %{value: value})

  @doc "Creates one Release or raises its error."
  @spec new!(t() | map() | keyword()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, release} -> release
      {:error, error} -> raise error
    end
  end

  @doc "Checks the Release document, Catalog identity, and content digest."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = release) do
    with {:ok, release} <- parse(release),
         :ok <- JSON.validate(release.document, [:document]),
         :ok <- JSON.validate(release.source, [:source]),
         :ok <- JSON.validate(release.metadata, [:metadata]),
         {:ok, definition} <- decode_definition(release.document),
         :ok <- matching_definition(release, definition),
         :ok <- matching_digest(release) do
      {:ok, release}
    end
  end

  def validate(value), do: invalid(:invalid_release, "Expected a Release", %{value: value})

  @doc "Encodes one verified Release as a portable database document."
  @spec encode(t()) :: {:ok, map()} | {:error, Exception.t()}
  def encode(%__MODULE__{} = release) do
    with {:ok, release} <- validate(release), do: {:ok, wire_document(release)}
  end

  def encode(value), do: invalid(:invalid_release, "Expected a Release", %{value: value})

  @doc "Encodes one verified Release as canonical JSON."
  @spec encode_json(t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def encode_json(%__MODULE__{} = release) do
    with {:ok, document} <- encode(release), do: JSON.encode_canonical(document)
  end

  def encode_json(value), do: invalid(:invalid_release, "Expected a Release", %{value: value})

  @doc "Decodes and verifies one portable Release document."
  @spec decode(map()) :: {:ok, t()} | {:error, Exception.t()}
  def decode(%{"type" => @document_type, "vsn" => @document_vsn} = document) do
    with :ok <- exact_wire_keys(document) do
      new(%{
        id: document["id"],
        digest: document["digest"],
        application_id: document["application_id"],
        build_id: document["build_id"],
        catalog: document["catalog"],
        catalog_digest: document["catalog_digest"],
        definition_version: document["definition_version"],
        document: document["document"],
        source: document["source"],
        metadata: document["metadata"]
      })
    end
  end

  def decode(value) do
    invalid(:invalid_release_document, "Release document is invalid", %{value: value})
  end

  @doc "Decodes and verifies one JSON Release document."
  @spec decode_json(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, document} ->
        decode(document)

      {:error, error} ->
        invalid(:invalid_release_json, "Release JSON is invalid", %{error: error})
    end
  end

  def decode_json(value) do
    invalid(:invalid_release_json, "Release JSON is invalid", %{value: value})
  end

  @doc "Decodes the frozen Definition."
  @spec definition(t(), keyword()) :: {:ok, Definition.t()} | {:error, Exception.t()}
  def definition(release, opts \\ [])

  def definition(%__MODULE__{} = release, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, release} <- validate(release),
           {:ok, definition} <- decode_definition(release.document),
           {:ok, definition} <- maybe_validate_catalog(release, definition, opts) do
        {:ok, definition}
      end
    else
      invalid(:invalid_options, "Release options must be a keyword list", %{options: opts})
    end
  end

  def definition(release, opts) do
    invalid(:invalid_release, "Release and options are invalid", %{
      release: release,
      options: opts
    })
  end

  @doc "Decodes the frozen Definition or raises its error."
  @spec definition!(t(), keyword()) :: Definition.t()
  def definition!(release, opts \\ []) do
    case definition(release, opts) do
      {:ok, definition} -> definition
      {:error, error} -> raise error
    end
  end

  defp freeze_definition(definition, opts) do
    with {:ok, application_id} <- required_option(opts, :application_id),
         {:ok, build_id} <- required_option(opts, :build_id),
         {:ok, catalog} <- required_catalog(opts),
         {:ok, definition} <- Jido.UI.define(definition, catalog: catalog),
         {:ok, catalog_digest} <- Catalog.digest(catalog),
         source <- Keyword.get(opts, :source, %{}),
         metadata <- Keyword.get(opts, :metadata, %{}),
         :ok <- JSON.validate(source, [:source]),
         :ok <- JSON.validate(metadata, [:metadata]),
         {:ok, document} <- encode_definition(definition),
         content = %{
           application_id: application_id,
           build_id: build_id,
           catalog: definition.catalog,
           catalog_digest: catalog_digest,
           definition_version: definition.vsn,
           document: document,
           source: source,
           metadata: metadata
         },
         {:ok, content_digest} <- content |> content_artifact() |> JSON.digest(),
         id <- Keyword.get(opts, :id, "release-#{String.slice(content_digest, 0, 16)}"),
         attrs <- Map.put(content, :id, id),
         {:ok, digest} <- attrs |> artifact() |> JSON.digest() do
      attrs |> Map.put(:digest, digest) |> new()
    end
  end

  defp parse(release) do
    case Zoi.parse(@schema, release) do
      {:ok, release} -> {:ok, release}
      {:error, issues} -> invalid(:invalid_release, "Release is invalid", %{issues: issues})
    end
  end

  defp required_option(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, value}

      value ->
        invalid(:invalid_release, "Release option is required", %{option: key, value: value})
    end
  end

  defp required_catalog(opts) do
    case Keyword.fetch(opts, :catalog) do
      {:ok, catalog} -> Catalog.resolve(catalog)
      :error -> invalid(:invalid_release, "Release Catalog is required", %{option: :catalog})
    end
  end

  defp encode_definition(definition) do
    case Jido.Authoring.encode(definition, codec: Codec, registry: registry()) do
      {:ok, document} ->
        {:ok, document}

      {:error, error} ->
        invalid(:release_encode_failed, "Definition could not be encoded", %{error: error})
    end
  end

  defp decode_definition(document) do
    case Jido.Authoring.decode(document, codec: Codec, registry: registry()) do
      {:ok, %Definition{} = definition} ->
        {:ok, definition}

      {:error, issues} ->
        invalid(:release_decode_failed, "Release document could not be decoded", %{issues: issues})
    end
  end

  defp matching_definition(release, definition) do
    cond do
      release.catalog != definition.catalog ->
        invalid(:release_catalog_mismatch, "Release Catalog does not match its Definition", %{
          expected: release.catalog,
          actual: definition.catalog
        })

      release.definition_version != definition.vsn ->
        invalid(
          :release_definition_version_mismatch,
          "Release version does not match its Definition",
          %{
            expected: release.definition_version,
            actual: definition.vsn
          }
        )

      true ->
        :ok
    end
  end

  defp maybe_validate_catalog(_release, definition, opts) when opts == [],
    do: Definition.validate(definition)

  defp maybe_validate_catalog(release, definition, opts) do
    case Keyword.get(opts, :catalog) do
      nil ->
        Definition.validate(definition)

      catalog ->
        with {:ok, catalog} <- Catalog.resolve(catalog),
             {:ok, digest} <- Catalog.digest(catalog),
             :ok <- matching_catalog_digest(release, digest),
             {:ok, definition} <- Jido.UI.define(definition, catalog: catalog) do
          {:ok, definition}
        end
    end
  end

  defp matching_catalog_digest(%{catalog_digest: digest}, digest), do: :ok

  defp matching_catalog_digest(release, actual) do
    invalid(:release_catalog_digest_mismatch, "Release Catalog content has changed", %{
      expected: release.catalog_digest,
      actual: actual
    })
  end

  defp matching_digest(release) do
    with {:ok, actual} <- release |> artifact() |> JSON.digest() do
      if actual == release.digest do
        :ok
      else
        invalid(:release_digest_mismatch, "Release content does not match its digest", %{
          expected: release.digest,
          actual: actual
        })
      end
    end
  end

  defp artifact(release) do
    Map.put(content_artifact(release), "id", release.id)
  end

  defp content_artifact(release) do
    %{
      "application_id" => release.application_id,
      "build_id" => release.build_id,
      "catalog" => release.catalog,
      "catalog_digest" => release.catalog_digest,
      "definition_version" => release.definition_version,
      "document" => release.document,
      "source" => release.source,
      "metadata" => release.metadata
    }
  end

  defp wire_document(release) do
    release
    |> artifact()
    |> Map.merge(%{
      "type" => @document_type,
      "vsn" => @document_vsn,
      "id" => release.id,
      "digest" => release.digest
    })
  end

  defp exact_wire_keys(document) do
    if Enum.sort(Map.keys(document)) == Enum.sort(@wire_keys) do
      :ok
    else
      invalid(:invalid_release_document, "Release document fields are invalid", %{
        fields: Map.keys(document)
      })
    end
  end

  defp registry, do: Jido.Authoring.Registry.new!(%{})

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
