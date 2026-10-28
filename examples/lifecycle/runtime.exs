defmodule JidoUI.Examples.Lifecycle.AdvanceTea do
  @moduledoc false

  use Jido.Action,
    name: "jido_ui_lifecycle_advance_tea",
    schema:
      Zoi.object(%{
        "surface_id" => Zoi.string(),
        "region_id" => Zoi.string(),
        "region_revision" => Zoi.integer() |> Zoi.min(0),
        "action_id" => Zoi.string(),
        "input" => Zoi.map()
      }),
    output_schema:
      Zoi.object(%{
        step: Zoi.integer() |> Zoi.min(0),
        history: Zoi.list(Zoi.string())
      })

  alias JidoUI.Examples.Lifecycle.Events

  @impl true
  def run(input, context) do
    step = context.agent_state.step + 1

    state = %{
      context.agent_state
      | step: step,
        history: context.agent_state.history ++ ["advanced-to-#{step}"]
    }

    event =
      Events.directive(
        "runtime.state_changed",
        %{
          "action_id" => input["action_id"],
          "build_id" => input["input"]["build_id"],
          "step" => step
        },
        context
      )

    {:ok, state, [event]}
  end
end

defmodule JidoUI.Examples.Lifecycle.TeaAgent do
  @moduledoc false

  use Jido.Agent,
    name: "jido_ui_lifecycle_tea",
    description: "Owns the state shown by one frozen UI release"

  state do
    schema(
      Zoi.object(%{
        step: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
        history: Zoi.list(Zoi.string()) |> Zoi.default([])
      })
    )
  end

  routes do
    signal_source("/examples/jido_ui/lifecycle/tea")
    route("tea.advance", JidoUI.Examples.Lifecycle.AdvanceTea, as: :advance)
  end
end

defmodule JidoUI.Examples.Lifecycle.RuntimeProjection do
  @moduledoc false

  alias Jido.UI.{Interaction, Release, Surface}
  alias JidoUI.Examples.Lifecycle.Catalog

  @statuses [
    "Warming the bowl",
    "Opening the leaves",
    "Ready to pour",
    "Session complete"
  ]

  def surface(release, snapshot, owner) do
    definition = Release.definition!(release, catalog: Catalog.catalog())

    {:ok, %{projection: projection}} =
      Jido.Exec.run(Jido.UI.Projection.Flow, %{
        definition: definition,
        data: view_model(snapshot.agent)
      })

    region =
      Jido.UI.instantiate!(projection,
        id: "tea-session",
        owner: owner,
        revision: snapshot.state_version,
        catalog: Catalog.catalog()
      )

    Surface.compose!("momentary-tea-surface", region, [],
      metadata: %{
        "release_id" => release.id,
        "release_digest" => release.digest
      }
    )
  end

  def interaction(surface) do
    region = surface.regions[surface.root_region]

    Interaction.new!(%{
      surface_id: surface.id,
      region_id: region.id,
      region_revision: region.revision,
      action_id: "advance",
      values: %{}
    })
  end

  def render(surface) do
    Jido.UI.Renderer.Text.render(surface, catalog: Catalog.catalog())
  end

  defp view_model(agent) do
    %{
      "title" => "A UI frozen for this tea session",
      "status" => Enum.at(@statuses, min(agent.state.step, length(@statuses) - 1))
    }
  end
end

defmodule JidoUI.Examples.Lifecycle.Example do
  @moduledoc false

  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.UI.Builder
  alias Jido.UI.Builder.Agent, as: BuilderAgent
  alias JidoUI.Examples.Lifecycle.{Catalog, Events, RuntimeProjection, TeaAgent}

  @instance JidoUI.Examples.Lifecycle.Jido
  @namespace "examples/jido_ui/lifecycle"
  @persistence {Jido.Persistence.ETS, table: :jido_ui_lifecycle_example}
  @observer JidoUI.Examples.Lifecycle.Observer

  def run do
    {:ok, _jido} = Jido.start(name: @instance, namespace: @namespace)
    register_observer!()

    try do
      run_id = System.unique_integer([:positive, :monotonic])
      builder_ref = ref!("builder-#{run_id}")
      tea_ref = ref!("tea-#{run_id}")
      dispatch = {:named, target: {:name, @observer}}

      {:ok, builder_server} =
        Jido.start_agent_ref(@instance, builder_ref, BuilderAgent,
          persistence: @persistence,
          persistence_mode: :create
        )

      {:ok, tea_server} =
        Jido.start_agent_ref(@instance, tea_ref, TeaAgent,
          persistence: @persistence,
          persistence_mode: :create
        )

      :ok = AgentServer.await_ready(builder_server)
      :ok = AgentServer.await_ready(tea_server)

      initial_tea = AgentServer.snapshot(tea_server)
      builder_context = Builder.catalog_context!(Catalog.catalog(), dispatch: dispatch)

      {:ok, start_signal} =
        Builder.start_signal(%{
          application_id: "examples/tea-session",
          goal: "Guide one user through the current tea session",
          catalog: Catalog.catalog().id,
          source: %{"owner" => Ref.to_map!(tea_ref)},
          source_state_revision: initial_tea.state_version
        })

      {:ok, started, _directives} =
        Jido.call(@instance, builder_ref, start_signal, context: builder_context)

      invalid_candidate = candidate(started.state.build["id"], %{"variant" => "primary"})
      {:ok, propose_signal} = Builder.propose_signal(invalid_candidate)

      {:ok, rejected, _directives} =
        Jido.call(@instance, builder_ref, propose_signal, context: builder_context)

      repaired_candidate =
        put_in(invalid_candidate, ["nodes", "advance", "props", "label"], "Continue")

      {:ok, propose_signal} = Builder.propose_signal(repaired_candidate)

      {:ok, _valid, _directives} =
        Jido.call(@instance, builder_ref, propose_signal, context: builder_context)

      {:ok, freeze_signal} = Builder.freeze_signal(%{"designed_by" => "static-example"})

      {:ok, _frozen, _directives} =
        Jido.call(@instance, builder_ref, freeze_signal, context: builder_context)

      {:ok, activate_signal} = Builder.activate_signal()

      {:ok, builder, _directives} =
        Jido.call(@instance, builder_ref, activate_signal, context: builder_context)

      {:ok, persisted_builder, persisted_builder_revision} =
        Jido.Persistence.load_agent_with_revision(
          @persistence,
          BuilderAgent,
          builder_ref.id,
          instance: @instance
        )

      release = persisted_builder.state.releases[persisted_builder.state.active_release_id]
      initial_surface = RuntimeProjection.surface(release, initial_tea, tea_ref)
      {:ok, initial_text} = RuntimeProjection.render(initial_surface)

      :ok =
        Events.dispatch(
          "runtime.projected",
          %{
            "agent_revision" => initial_tea.state_version,
            "release_id" => release.id
          },
          dispatch
        )

      interaction = RuntimeProjection.interaction(initial_surface)
      {:ok, owner, signal} = Jido.UI.route(interaction, initial_surface)

      :ok =
        Events.dispatch(
          "runtime.interaction_routed",
          %{
            "action_id" => interaction.action_id,
            "owner_id" => owner.id,
            "signal_type" => signal.type
          },
          dispatch
        )

      {:ok, _tea, _directives} =
        Jido.call(@instance, owner, signal, context: %{lifecycle_dispatch: dispatch})

      next_tea = AgentServer.snapshot(tea_server)
      next_surface = RuntimeProjection.surface(release, next_tea, tea_ref)
      {:ok, next_text} = RuntimeProjection.render(next_surface)

      :ok =
        Events.dispatch(
          "runtime.projected",
          %{
            "agent_revision" => next_tea.state_version,
            "release_id" => release.id
          },
          dispatch
        )

      stale_interaction_result = Jido.UI.route(interaction, next_surface)
      events = Events.drain()

      %{
        builder: builder,
        rejected: rejected,
        persisted_builder_revision: persisted_builder_revision,
        release: release,
        initial_surface: initial_surface,
        initial_text: initial_text,
        next_surface: next_surface,
        next_text: next_text,
        stale_interaction_result: stale_interaction_result,
        events: events
      }
    after
      Jido.stop(@instance)
      unregister_observer()
    end
  end

  defp candidate(build_id, button_props) do
    %{
      "name" => "momentary-tea-ui",
      "description" => "A UI for one tea session",
      "catalog" => Catalog.catalog().id,
      "root" => "root",
      "nodes" => %{
        "root" => %{
          "component" => "stack",
          "props" => %{"gap" => "large"},
          "children" => ["title", "status", "advance"]
        },
        "title" => %{
          "component" => "heading",
          "props" => %{"text" => Jido.UI.bind("/title"), "level" => 1}
        },
        "status" => %{
          "component" => "notice",
          "props" => %{
            "title" => "Current moment",
            "text" => Jido.UI.bind("/status"),
            "tone" => "positive"
          }
        },
        "advance" => %{
          "component" => "button",
          "props" => button_props,
          "events" => %{"activate" => "advance"}
        }
      },
      "intents" => %{
        "advance" => %{
          "capability" => "tea.advance",
          "input" => %{"build_id" => build_id}
        }
      },
      "metadata" => %{"generated_by" => "static-example"}
    }
  end

  defp ref!(id) do
    {:ok, ref} = Jido.agent_ref(@instance, id)
    ref
  end

  defp register_observer! do
    true = Process.register(self(), @observer)
  end

  defp unregister_observer do
    if Process.whereis(@observer) == self(), do: Process.unregister(@observer)
  end
end
