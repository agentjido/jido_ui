defmodule Jido.UI.Builder do
  @moduledoc """
  Public authoring boundary for persistent UI Builder Agents.

  A Builder Agent owns editable draft metadata and immutable Releases. An AI
  harness can use `authoring_packet/2` to produce or repair a candidate, then
  submit that candidate with `propose_signal/1`.
  """

  alias Jido.Agent.Directive
  alias Jido.Signal
  alias Jido.UI.{Catalog, Definition, Error, Release}
  alias Jido.UI.Authoring.Codec
  alias Jido.UI.Builder.{Agent, State}

  @start_schema Zoi.object(%{
                  application_id: Zoi.string() |> Zoi.min(1),
                  goal: Zoi.string() |> Zoi.min(1),
                  catalog: Zoi.string() |> Zoi.min(1),
                  source: Zoi.map() |> Zoi.default(%{}),
                  source_state_revision:
                    Zoi.integer() |> Zoi.min(0) |> Zoi.nullable() |> Zoi.default(nil)
                })
  @propose_schema Zoi.object(%{candidate: Zoi.map()})
  @freeze_schema Zoi.object(%{metadata: Zoi.map() |> Zoi.default(%{})})
  @activate_schema Zoi.object(%{
                     release_id: Zoi.string() |> Zoi.min(1) |> Zoi.nullable() |> Zoi.default(nil)
                   })
  @build_schema Zoi.object(
                  %{
                    "id" => Zoi.string() |> Zoi.min(1),
                    "application_id" => Zoi.string() |> Zoi.min(1),
                    "goal" => Zoi.string() |> Zoi.min(1),
                    "catalog" => Zoi.string() |> Zoi.min(1),
                    "source" => Zoi.map(),
                    "source_state_revision" => Zoi.integer() |> Zoi.min(0) |> Zoi.nullable()
                  },
                  unrecognized_keys: :error
                )

  @doc "Returns a Signal that starts a new editable build."
  defdelegate start_signal(input), to: Agent, as: :start_signal

  @doc "Returns a Signal that proposes a complete candidate Definition."
  @spec propose_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def propose_signal(candidate), do: Agent.propose_signal(%{candidate: candidate})

  @doc "Returns a Signal that freezes the current valid Definition."
  @spec freeze_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def freeze_signal(metadata \\ %{}), do: Agent.freeze_signal(%{metadata: metadata})

  @doc "Returns a Signal that activates a stored Release."
  @spec activate_signal(String.t() | nil) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def activate_signal(release_id \\ nil), do: Agent.activate_signal(%{release_id: release_id})

  @doc "Builds trusted execution context for one application Catalog."
  @spec catalog_context(Catalog.t() | module(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def catalog_context(catalog, opts \\ [])

  def catalog_context(catalog, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, resolved} <- Catalog.resolve(catalog) do
        jido_ui =
          %{catalogs: %{resolved.id => resolved}}
          |> maybe_put_dispatch(Keyword.get(opts, :dispatch))

        {:ok, %{jido_ui: jido_ui}}
      end
    else
      invalid(:invalid_options, "Builder context options must be a keyword list", %{options: opts})
    end
  end

  def catalog_context(_catalog, opts) do
    invalid(:invalid_options, "Builder context options must be a keyword list", %{options: opts})
  end

  @doc "Builds trusted Catalog context or raises its error."
  @spec catalog_context!(Catalog.t() | module(), keyword()) :: map()
  def catalog_context!(catalog, opts \\ []) do
    case catalog_context(catalog, opts) do
      {:ok, context} -> context
      {:error, error} -> raise error
    end
  end

  @doc "Returns portable Builder context for an external design harness."
  @spec authoring_packet(map(), Catalog.t() | module()) ::
          {:ok, map()} | {:error, Error.t()}
  def authoring_packet(state, catalog) when is_map(state) do
    with {:ok, state} <- parse_builder_state(state),
         {:ok, build} <- authoring_build(state),
         {:ok, catalog} <- Catalog.resolve(catalog),
         {:ok, catalog} <- matching_catalog(build["catalog"], catalog),
         {:ok, catalog_document} <- authoring_catalog_document(catalog),
         {:ok, output_schema} <- output_schema(catalog) do
      packet = %{
        "application_id" => build["application_id"],
        "build_id" => build["id"],
        "goal" => build["goal"],
        "status" => state.status,
        "proposal_revision" => state.proposal_revision,
        "catalog" => catalog_document,
        "candidate" => state.draft,
        "diagnostics" => state.diagnostics,
        "output_schema" => output_schema
      }

      with :ok <- Jido.UI.JSON.validate(packet), do: {:ok, packet}
    end
  end

  def authoring_packet(state, _catalog) do
    invalid(:invalid_builder_state, "Builder state must be a map", %{state: state})
  end

  @doc "Returns portable Builder context or raises its error."
  @spec authoring_packet!(map(), Catalog.t() | module()) :: map()
  def authoring_packet!(state, catalog) do
    case authoring_packet(state, catalog) do
      {:ok, packet} -> packet
      {:error, error} -> raise error
    end
  end

  @doc "Returns the JSON Schema for one complete candidate Definition."
  @spec output_schema(Catalog.t() | module()) :: {:ok, map()} | {:error, Error.t()}
  def output_schema(catalog) do
    with {:ok, catalog} <- Catalog.resolve(catalog),
         {:ok, document} <- Catalog.document(catalog) do
      schema = definition_output_schema(catalog, document["components"])

      with :ok <- Jido.UI.JSON.validate(schema), do: {:ok, schema}
    end
  end

  @doc false
  def start_schema, do: @start_schema

  @doc false
  def propose_schema, do: @propose_schema

  @doc false
  def freeze_schema, do: @freeze_schema

  @doc false
  def activate_schema, do: @activate_schema

  @doc false
  def begin_build(input, context) do
    with {:ok, _catalog} <- resolve_catalog(input.catalog, context) do
      state = context.agent_state

      build = %{
        "id" => context.signal.id,
        "application_id" => input.application_id,
        "goal" => input.goal,
        "catalog" => input.catalog,
        "source" => input.source,
        "source_state_revision" => input.source_state_revision
      }

      next = %{
        state
        | status: "drafting",
          build: build,
          proposal_revision: 0,
          draft: %{},
          definition: nil,
          diagnostics: [],
          release: nil
      }

      {:ok, next, emit("build.started", next, %{}, context)}
    end
  end

  @doc false
  def record_draft(candidate, context) do
    state = context.agent_state

    with :ok <- allow_status(state, ["drafting", "invalid", "valid"], "propose a candidate") do
      next = %{
        state
        | status: "drafting",
          proposal_revision: state.proposal_revision + 1,
          draft: candidate,
          definition: nil,
          diagnostics: [],
          release: nil
      }

      {:ok, %{state: next}, emit("candidate.proposed", next, %{}, context)}
    end
  end

  @doc false
  def validate_draft(state, context) do
    with {:ok, catalog} <- resolve_catalog(state.build["catalog"], context) do
      case Jido.UI.define(state.draft, catalog: catalog) do
        {:ok, definition} -> accept_definition(state, definition, context)
        {:error, error} -> reject_definition(state, error, context)
      end
    end
  end

  @doc false
  def freeze_release(metadata, context) do
    state = context.agent_state

    with :ok <- allow_status(state, ["valid"], "freeze a Release"),
         {:ok, catalog} <- resolve_catalog(state.build["catalog"], context),
         {:ok, definition} <- decode_definition(state.definition),
         {:ok, definition} <- Jido.UI.define(definition, catalog: catalog),
         {:ok, release} <-
           Release.freeze(definition,
             application_id: state.build["application_id"],
             build_id: state.build["id"],
             catalog: catalog,
             source: source_metadata(state.build),
             metadata: metadata
           ) do
      next = %{state | status: "frozen", release: release}

      {:ok, %{state: next},
       emit(
         "release.frozen",
         next,
         %{"release_id" => release.id, "digest" => release.digest},
         context
       )}
    end
  end

  @doc false
  def store_release(state, context) do
    release = state.release
    next = %{state | releases: Map.put(state.releases, release.id, release)}
    {:ok, %{state: next}, emit("release.stored", next, %{"release_id" => release.id}, context)}
  end

  @doc false
  def activate_release(input, context) do
    state = context.agent_state
    release_id = input.release_id || current_release_id(state)

    case Map.fetch(state.releases, release_id) do
      {:ok, release} ->
        next = %{state | active_release_id: release.id}
        {:ok, next, emit("release.activated", next, %{"release_id" => release.id}, context)}

      :error ->
        invalid(:unknown_release, "Builder cannot activate an unknown Release", %{
          release_id: release_id
        })
    end
  end

  @doc false
  def resolve_catalog(id, context) when is_binary(id) do
    catalogs = get_in(context, [:jido_ui, :catalogs]) || %{}

    case Map.get(catalogs, id) do
      nil -> Catalog.resolve(id)
      catalog -> matching_catalog(id, catalog)
    end
  end

  defp accept_definition(state, definition, context) do
    case encode_definition(definition) do
      {:ok, document} ->
        next = %{state | status: "valid", definition: document, diagnostics: []}
        {:ok, %{state: next}, emit("candidate.validated", next, %{}, context)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp reject_definition(state, error, context) do
    diagnostic = diagnostic(error)
    next = %{state | status: "invalid", definition: nil, diagnostics: [diagnostic]}

    {:ok, %{state: next},
     emit("candidate.rejected", next, %{"diagnostic" => diagnostic}, context)}
  end

  defp encode_definition(%Definition{} = definition) do
    Jido.Authoring.encode(definition,
      codec: Codec,
      registry: Jido.Authoring.Registry.new!(%{})
    )
  end

  defp decode_definition(document) do
    case Jido.Authoring.decode(document,
           codec: Codec,
           registry: Jido.Authoring.Registry.new!(%{})
         ) do
      {:ok, %Definition{} = definition} ->
        {:ok, definition}

      {:error, issues} ->
        invalid(:invalid_builder_definition, "Builder Definition cannot be decoded", %{
          issues: issues
        })
    end
  end

  defp matching_catalog(id, catalog) do
    with {:ok, catalog} <- Catalog.resolve(catalog) do
      if catalog.id == id do
        {:ok, catalog}
      else
        invalid(:catalog_mismatch, "Builder Catalog does not match the build", %{
          expected: id,
          actual: catalog.id
        })
      end
    end
  end

  defp allow_status(state, allowed, operation) do
    if state.status in allowed do
      :ok
    else
      invalid(
        :invalid_builder_transition,
        "Builder cannot #{operation} from its current state",
        %{
          status: state.status,
          allowed: allowed
        }
      )
    end
  end

  defp current_release_id(%{release: %Release{id: id}}), do: id
  defp current_release_id(_state), do: nil

  defp source_metadata(build) do
    %{
      "input" => build["source"],
      "state_revision" => build["source_state_revision"]
    }
  end

  defp diagnostic(error) do
    %{
      "code" => error |> Map.get(:code, :validation_failed) |> to_string(),
      "message" => Exception.message(error),
      "path" => error |> Map.get(:path, []) |> Enum.map(&to_string/1),
      "details" => error |> Map.get(:details, %{}) |> portable_detail()
    }
  end

  defp portable_detail(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: value

  defp portable_detail(value) when is_atom(value), do: Atom.to_string(value)
  defp portable_detail(values) when is_list(values), do: Enum.map(values, &portable_detail/1)

  defp portable_detail(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, item} -> {to_string(key), portable_detail(item)} end)
  end

  defp portable_detail(value), do: inspect(value)

  defp emit(stage, state, data, context) do
    case get_in(context, [:jido_ui, :dispatch]) do
      nil ->
        []

      dispatch ->
        signal =
          Signal.new!(
            "jido.ui.builder.#{stage}",
            Map.merge(
              %{
                "application_id" => state.build["application_id"],
                "build_id" => state.build["id"],
                "status" => state.status,
                "proposal_revision" => state.proposal_revision
              },
              data
            ),
            source: "/jido/ui/builder"
          )

        [Directive.emit(signal, dispatch)]
    end
  end

  defp maybe_put_dispatch(context, nil), do: context
  defp maybe_put_dispatch(context, dispatch), do: Map.put(context, :dispatch, dispatch)

  defp parse_builder_state(state) do
    case Zoi.parse(State.schema(), state) do
      {:ok, state} ->
        {:ok, state}

      {:error, issues} ->
        invalid(:invalid_builder_state, "Builder state is invalid", %{issues: issues})
    end
  end

  defp authoring_build(%{status: status, build: build})
       when status in ["drafting", "invalid", "valid"] do
    case Zoi.parse(@build_schema, build) do
      {:ok, build} ->
        {:ok, build}

      {:error, issues} ->
        invalid(:invalid_builder_state, "Builder build data is invalid", %{issues: issues})
    end
  end

  defp authoring_build(%{status: status}) do
    invalid(:invalid_builder_transition, "Builder cannot produce an authoring packet", %{
      status: status,
      allowed: ["drafting", "invalid", "valid"]
    })
  end

  defp authoring_catalog_document(catalog) do
    with {:ok, document} <- Catalog.document(catalog) do
      capabilities =
        Map.new(catalog.capabilities, fn {id, capability} ->
          {id,
           %{
             "accepts" => capability.accepts,
             "risk" => Atom.to_string(capability.risk)
           }}
        end)

      {:ok,
       %{
         "id" => catalog.id,
         "components" => document["components"],
         "capabilities" => capabilities
       }}
    end
  end

  defp definition_output_schema(catalog, component_schemas) do
    child = %{
      "oneOf" => [
        %{"type" => "string", "minLength" => 1},
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["kind", "id"],
          "properties" => %{
            "kind" => %{"enum" => ["node", "region"]},
            "id" => %{"type" => "string", "minLength" => 1}
          }
        }
      ]
    }

    node_variants =
      component_schemas
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {id, props_schema} ->
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["component"],
          "properties" => %{
            "component" => %{"const" => id},
            "props" => Map.delete(props_schema, "$schema"),
            "children" => %{"type" => "array", "items" => child},
            "events" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string", "minLength" => 1}
            }
          }
        }
      end)

    capability_ids = catalog.capabilities |> Map.keys() |> Enum.sort()

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["name", "catalog", "root", "nodes"],
      "properties" => %{
        "name" => %{"type" => "string", "minLength" => 1},
        "description" => %{"type" => ["string", "null"]},
        "vsn" => %{"type" => "integer", "minimum" => 1},
        "catalog" => %{"const" => catalog.id},
        "root" => %{"type" => "string", "minLength" => 1},
        "nodes" => %{
          "type" => "object",
          "minProperties" => 1,
          "propertyNames" => %{"type" => "string", "minLength" => 1},
          "additionalProperties" => %{"oneOf" => node_variants}
        },
        "intents" => %{
          "type" => "object",
          "propertyNames" => %{"type" => "string", "minLength" => 1},
          "additionalProperties" => intent_schema(capability_ids)
        },
        "metadata" => %{"type" => "object"}
      }
    }
  end

  defp intent_schema([]), do: %{"not" => %{}}

  defp intent_schema(capability_ids) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["capability"],
      "properties" => %{
        "capability" => %{"enum" => capability_ids},
        "input" => %{"type" => "object"}
      }
    }
  end

  defp invalid(code, message, details) do
    {:error, Error.new(code, message, details: details)}
  end
end
