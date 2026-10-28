defmodule Jido.UI.BuilderTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.UI.{Builder, Release}
  alias Jido.UI.Builder.Agent, as: BuilderAgent
  alias JidoUITest.Fixtures

  @instance __MODULE__.Jido
  @persistence {Jido.Persistence.ETS, table: :jido_ui_builder_test}

  setup do
    start_supervised!(
      {Jido, name: @instance, namespace: "test/jido_ui/builder"},
      id: @instance
    )

    id = "builder-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, ref} = Jido.agent_ref(@instance, id)

    {:ok, server} =
      Jido.start_agent_ref(@instance, ref, BuilderAgent,
        persistence: @persistence,
        persistence_mode: :create
      )

    :ok = AgentServer.await_ready(server)

    %{ref: ref, server: server, catalog: Fixtures.catalog()}
  end

  test "a persistent Builder Agent accepts repair, freezes, and activates a UI", context do
    builder_context = Builder.catalog_context!(context.catalog)

    {:ok, start_signal} =
      Builder.start_signal(%{
        application_id: "jidoka/harness",
        goal: "Build one agent task view",
        catalog: context.catalog.id,
        source: %{"actor_id" => "actor-1"},
        source_state_revision: 7
      })

    assert {:ok, started, _directives} = call(context.ref, start_signal, builder_context)
    assert started.state.status == "drafting"
    assert started.state.active_release_id == nil

    invalid = candidate(%{})
    {:ok, propose_signal} = Builder.propose_signal(invalid)

    assert {:ok, rejected, _directives} = call(context.ref, propose_signal, builder_context)
    assert rejected.state.status == "invalid"
    assert rejected.state.proposal_revision == 1
    assert [%{"code" => "invalid_component_props"}] = rejected.state.diagnostics

    packet = Builder.authoring_packet!(rejected.state, context.catalog)
    assert packet["goal"] == "Build one agent task view"
    assert packet["candidate"] == invalid
    assert packet["catalog"]["capabilities"]["workspace.continue"]["accepts"] == ["note"]

    assert packet["output_schema"]["properties"]["catalog"] == %{
             "const" => "jido.ui.basic/v1"
           }

    assert {:ok, _json} = Jason.encode(packet)

    valid = candidate(%{"label" => "Continue", "variant" => "primary"})
    {:ok, propose_signal} = Builder.propose_signal(valid)

    assert {:ok, accepted, _directives} = call(context.ref, propose_signal, builder_context)
    assert accepted.state.status == "valid"
    assert accepted.state.proposal_revision == 2
    assert accepted.state.diagnostics == []
    assert accepted.state.definition["type"] == "jido.ui.definition"

    {:ok, freeze_signal} = Builder.freeze_signal(%{"designed_by" => "jidoka-harness"})
    assert {:ok, frozen, _directives} = call(context.ref, freeze_signal, builder_context)

    assert frozen.state.status == "frozen"
    assert %Release{} = release = frozen.state.release
    assert frozen.state.releases[release.id] == release
    assert release.application_id == "jidoka/harness"
    assert release.metadata == %{"designed_by" => "jidoka-harness"}

    definition = Release.definition!(release, catalog: context.catalog)
    assert definition.nodes["continue"].props["label"] == "Continue"

    {:ok, activate_signal} = Builder.activate_signal()
    assert {:ok, activated, _directives} = call(context.ref, activate_signal, builder_context)
    assert activated.state.active_release_id == release.id

    assert {:ok, persisted, persisted_revision} =
             Jido.Persistence.load_agent_with_revision(
               @persistence,
               BuilderAgent,
               context.ref.id,
               instance: @instance
             )

    assert persisted_revision >= 5
    assert persisted.state.active_release_id == release.id
    assert persisted.state.releases[release.id] == release
  end

  test "a Release detects changes to frozen content" do
    definition = Fixtures.root_definition()

    assert {:ok, release} =
             Release.freeze(definition,
               application_id: "release-test",
               build_id: "build-1",
               catalog: Fixtures.catalog(),
               source: %{"revision" => 1}
             )

    assert {:ok, ^release} = Release.validate(release)

    changed = %{release | metadata: %{"changed" => true}}

    assert {:error, %Jido.UI.Error{code: :release_digest_mismatch}} =
             Release.validate(changed)
  end

  test "a Release has a strict JSON wire format" do
    assert {:ok, release} =
             Release.freeze(Fixtures.root_definition(),
               application_id: "release-wire-test",
               build_id: "build-1",
               catalog: Fixtures.catalog(),
               source: %{"revision" => 1}
             )

    assert {:ok, document} = Release.encode(release)
    assert document["type"] == "jido.ui.release"
    assert document["vsn"] == 1
    assert document["catalog_digest"] == release.catalog_digest
    assert Enum.all?(Map.keys(document), &is_binary/1)
    assert {:ok, ^release} = Release.decode(document)

    assert {:ok, json} = Release.encode_json(release)
    assert {:ok, ^release} = Release.decode_json(json)

    tampered = put_in(document, ["metadata", "changed"], true)

    assert {:error, %Jido.UI.Error{code: :release_digest_mismatch}} =
             Release.decode(tampered)

    assert {:error, %Jido.UI.Error{code: :release_digest_mismatch}} =
             release |> Map.put(:id, "changed-release-id") |> Release.validate()

    assert {:error, %Jido.UI.Error{code: :invalid_release_document}} =
             document |> Map.put("unknown", true) |> Release.decode()
  end

  test "a Release is pinned to the exact Catalog content" do
    catalog = Fixtures.catalog()

    assert {:ok, release} =
             Release.freeze(Fixtures.root_definition(),
               application_id: "catalog-pin-test",
               build_id: "build-1",
               catalog: catalog
             )

    capability = %{catalog.capabilities["workspace.continue"] | risk: :guarded}

    changed_catalog = %{
      catalog
      | capabilities: Map.put(catalog.capabilities, "workspace.continue", capability)
    }

    assert {:error, %Jido.UI.Error{code: :release_catalog_digest_mismatch}} =
             Release.definition(release, catalog: changed_catalog)
  end

  test "the authoring packet requires an active build and its exact Catalog" do
    idle_state = Zoi.parse!(Jido.UI.Builder.State.schema(), %{})

    assert {:error, %Jido.UI.Error{code: :invalid_builder_transition}} =
             Builder.authoring_packet(idle_state, Fixtures.catalog())

    state = %{
      idle_state
      | status: "drafting",
        build: %{
          "id" => "build-1",
          "application_id" => "packet-test",
          "goal" => "Build a test UI",
          "catalog" => Fixtures.catalog().id,
          "source" => %{},
          "source_state_revision" => nil
        }
    }

    other_catalog = %{Fixtures.catalog() | id: "other/v1"}

    assert {:error, %Jido.UI.Error{code: :catalog_mismatch}} =
             Builder.authoring_packet(state, other_catalog)
  end

  test "new public boundaries return errors for malformed options" do
    assert {:error, %Jido.UI.Error{code: :invalid_options}} =
             Builder.catalog_context(Fixtures.catalog(), [:not_a_keyword])

    assert {:error, %Jido.UI.Error{code: :invalid_options}} =
             Release.freeze(Fixtures.root_definition(), [:not_a_keyword])
  end

  defp call(ref, signal, context) do
    Jido.call(@instance, ref, signal, context: context)
  end

  defp candidate(button_props) do
    %{
      "name" => "harness-task",
      "description" => "A candidate proposed by an external design harness",
      "catalog" => "jido.ui.basic/v1",
      "root" => "root",
      "nodes" => %{
        "root" => %{
          "component" => "stack",
          "props" => %{"gap" => "large"},
          "children" => ["title", "continue"]
        },
        "title" => %{
          "component" => "heading",
          "props" => %{"text" => "Harness task", "level" => 1}
        },
        "continue" => %{
          "component" => "button",
          "props" => button_props,
          "events" => %{"activate" => "continue"}
        }
      },
      "intents" => %{
        "continue" => %{
          "capability" => "workspace.continue",
          "input" => %{"mode" => "harness"}
        }
      },
      "metadata" => %{"proposed_by" => "test-harness"}
    }
  end
end
