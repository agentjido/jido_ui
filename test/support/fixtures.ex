defmodule JidoUITest.Fixtures do
  alias Jido.UI.{Catalog, Child}
  alias Jido.UI.Catalog.{Basic, Capability}

  def catalog do
    basic = Basic.catalog()

    capabilities = %{
      "workspace.continue" =>
        Capability.new!(%{
          id: "workspace.continue",
          event: "workspace.continue",
          accepts: ["note"]
        }),
      "worker.refresh" =>
        Capability.new!(%{
          id: "worker.refresh",
          event: "worker.refresh"
        }),
      "ui.inspect" => basic.capabilities["ui.inspect"]
    }

    Catalog.new!(basic.id, basic.components, capabilities)
  end

  def root_owner do
    Jido.Agent.Ref.new!(namespace: "test/ui", id: "workspace-1")
  end

  def child_owner do
    Jido.Agent.Ref.new!(namespace: "test/ui", id: "worker-1")
  end

  def root_definition do
    Jido.UI.define!(
      %{
        name: "workspace",
        description: "Root workspace",
        catalog: "jido.ui.basic/v1",
        root: "root",
        nodes: %{
          "root" => %{
            component: "stack",
            children: ["title", Child.region("worker"), "actions"]
          },
          "title" => %{
            component: "heading",
            props: %{"text" => Jido.UI.bind("/title"), "level" => 1}
          },
          "actions" => %{component: "action_bar", children: ["continue"]},
          "continue" => %{
            component: "button",
            props: %{"label" => "Continue", "variant" => "primary"},
            events: %{"activate" => "continue"}
          }
        },
        intents: %{
          "continue" => %{
            capability: "workspace.continue",
            input: %{"mode" => Jido.UI.bind("/selection")}
          }
        }
      },
      catalog: catalog()
    )
  end

  def child_definition do
    Jido.UI.define!(
      %{
        name: "worker",
        catalog: "jido.ui.basic/v1",
        root: "root",
        nodes: %{
          "root" => %{component: "stack", children: ["status", "refresh"]},
          "status" => %{
            component: "notice",
            props: %{
              "title" => "Research agent",
              "text" => Jido.UI.bind("/status"),
              "tone" => "positive"
            }
          },
          "refresh" => %{
            component: "button",
            props: %{"label" => "Refresh", "variant" => "quiet"},
            events: %{"activate" => "refresh"}
          }
        },
        intents: %{
          "refresh" => %{capability: "worker.refresh"}
        }
      },
      catalog: catalog()
    )
  end

  def root_projection do
    Jido.UI.project!(root_definition(), %{
      "title" => "Agent workspace",
      "selection" => "local"
    })
  end

  def child_projection do
    Jido.UI.project!(child_definition(), %{"status" => "Ready"})
  end

  def root_region do
    Jido.UI.instantiate!(root_projection(),
      id: "workspace",
      owner: root_owner(),
      revision: 7,
      catalog: catalog()
    )
  end

  def child_region do
    Jido.UI.instantiate!(child_projection(),
      id: "worker",
      owner: child_owner(),
      revision: 3,
      catalog: catalog()
    )
  end

  def surface do
    Jido.UI.Surface.compose!("agent-workspace", root_region(), [child_region()])
  end

  def projected_definition do
    Jido.UI.define!(
      %{
        name: "projected",
        catalog: "jido.ui.basic/v1",
        root: "root",
        nodes: %{
          "root" => %{
            component: "text",
            props: %{"text" => Jido.UI.bind("/label")}
          }
        }
      },
      catalog: catalog()
    )
  end
end

defmodule JidoUITest.Agent do
  use Jido.Agent, name: "ui_test_agent"

  state do
    schema(Zoi.object(%{label: Zoi.string() |> Zoi.default("Test")}))
  end
end

defmodule JidoUITest.Projector do
  @behaviour Jido.UI.Agent.Projector

  @impl true
  def project(agent, _context) do
    Jido.UI.project(JidoUITest.Fixtures.projected_definition(), %{
      "label" => agent.state.label
    })
  end
end
