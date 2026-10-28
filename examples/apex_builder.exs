defmodule JidoUI.Examples.ApexBuilder.Harness do
  @moduledoc false

  # A Jidoka harness can replace this function with a model call. The packet is
  # JSON-safe. It contains the goal, catalog, prior candidate, and diagnostics.
  def propose(%{"diagnostics" => []}), do: candidate(%{})

  def propose(%{"diagnostics" => [_diagnostic | _rest]}) do
    candidate(%{"label" => "Inspect session", "variant" => "primary"})
  end

  defp candidate(button_props) do
    %{
      "name" => "jidoka-session",
      "description" => "A UI designed for the current Jidoka session",
      "catalog" => "jido.ui.basic/v1",
      "root" => "root",
      "nodes" => %{
        "root" => %{
          "component" => "stack",
          "props" => %{"gap" => "large"},
          "children" => ["title", "summary", "inspect"]
        },
        "title" => %{
          "component" => "heading",
          "props" => %{"text" => "Jidoka session", "level" => 1}
        },
        "summary" => %{
          "component" => "text",
          "props" => %{"text" => "The Builder Agent froze this interface."}
        },
        "inspect" => %{
          "component" => "button",
          "props" => button_props,
          "events" => %{"activate" => "inspect"}
        }
      },
      "intents" => %{
        "inspect" => %{
          "capability" => "ui.inspect",
          "input" => %{"target" => "current-session"}
        }
      },
      "metadata" => %{"proposed_by" => "jidoka-harness"}
    }
  end
end

defmodule JidoUI.Examples.ApexBuilder do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.UI.{Builder, Release}
  alias Jido.UI.Builder.Agent, as: BuilderAgent
  alias Jido.UI.Catalog.Basic
  alias JidoUI.Examples.ApexBuilder.Harness

  @instance __MODULE__.Jido
  @persistence {Jido.Persistence.ETS, table: :jido_ui_apex_builder_example}

  def run(harness \\ &Harness.propose/1) when is_function(harness, 1) do
    {:ok, _jido} = Jido.start(name: @instance, namespace: "examples/jido_ui/apex-builder")

    try do
      {:ok, ref} = Jido.agent_ref(@instance, "builder-#{unique_id()}")

      {:ok, server} =
        Jido.start_agent_ref(@instance, ref, BuilderAgent,
          persistence: @persistence,
          persistence_mode: :create
        )

      :ok = AgentServer.await_ready(server)
      context = Builder.catalog_context!(Basic)

      {:ok, start_signal} =
        Builder.start_signal(%{
          application_id: "jidoka/session-harness",
          goal: "Design a focused interface for the current Jidoka session",
          catalog: Basic.catalog().id,
          source: %{"session_id" => "session-42"},
          source_state_revision: 12
        })

      {:ok, started, _directives} = Jido.call(@instance, ref, start_signal, context: context)

      first_packet = Builder.authoring_packet!(started.state, Basic)
      {:ok, first_signal} = first_packet |> harness.() |> Builder.propose_signal()
      {:ok, rejected, _directives} = Jido.call(@instance, ref, first_signal, context: context)

      repair_packet = Builder.authoring_packet!(rejected.state, Basic)
      {:ok, repair_signal} = repair_packet |> harness.() |> Builder.propose_signal()
      {:ok, valid, _directives} = Jido.call(@instance, ref, repair_signal, context: context)

      {:ok, freeze_signal} = Builder.freeze_signal(%{"designed_by" => "jidoka-harness"})
      {:ok, frozen, _directives} = Jido.call(@instance, ref, freeze_signal, context: context)

      {:ok, activate_signal} = Builder.activate_signal()
      {:ok, active, _directives} = Jido.call(@instance, ref, activate_signal, context: context)

      release = active.state.releases[active.state.active_release_id]

      %{
        first_packet: first_packet,
        repair_packet: repair_packet,
        valid_builder: valid,
        frozen_builder: frozen,
        active_builder: active,
        release: release,
        definition: Release.definition!(release, catalog: Basic)
      }
    after
      Jido.stop(@instance)
    end
  end

  defp unique_id, do: System.unique_integer([:positive, :monotonic])
end

result = JidoUI.Examples.ApexBuilder.run()

IO.puts("""

APEX builder spike
------------------
first proposal: #{result.repair_packet["status"]}
diagnostic: #{get_in(result.repair_packet, ["diagnostics", Access.at(0), "code"])}
repaired proposal: #{result.valid_builder.state.status}
release: #{result.release.id}
digest: #{result.release.digest}
active release: #{result.active_builder.state.active_release_id}
root node: #{result.definition.root}
""")
