defmodule Jido.UI.RenderingTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Jido.UI.Renderer.Text
  alias JidoUITest.Fixtures

  setup do
    original = Application.get_env(:jido_ui, Jido.UI.LiveView)

    on_exit(fn ->
      if original do
        Application.put_env(:jido_ui, Jido.UI.LiveView, original)
      else
        Application.delete_env(:jido_ui, Jido.UI.LiveView)
      end
    end)

    :ok
  end

  test "the text renderer consumes a complete Surface" do
    assert {:ok, text} = Text.render(Fixtures.surface(), catalog: Fixtures.catalog())
    assert text =~ "Agent workspace"
    assert text =~ "Research agent: Ready"
  end

  test "the LiveView renderer keeps Region revision routing data" do
    html =
      render_component(&Jido.UI.LiveView.surface/1,
        surface: Fixtures.surface(),
        components: JidoUITest.LiveComponents
      )

    assert html =~ ~s(data-jido-surface="agent-workspace")
    assert html =~ ~s(data-jido-region="worker")
    assert html =~ ~s(data-jido-agent-id="worker-1")
    assert html =~ ~s(phx-value-region-revision="3")
    refute html =~ "surface-revision"
  end

  test "a DaisyUI Theme adds classes without changing component markup" do
    html =
      render_component(&Jido.UI.LiveView.surface/1,
        surface: Fixtures.surface(),
        components: JidoUITest.LiveComponents,
        theme: {Jido.UI.LiveView.Theme.DaisyUI, name: "cupcake"}
      )

    assert html =~ ~s(data-theme="cupcake")
    assert html =~ ~s(class="btn btn-primary")
    assert html =~ ~s(class="alert alert-success")
    assert html =~ ~s(phx-value-region-revision="7")
  end

  test "application configuration provides the global ComponentSet and Theme" do
    Application.put_env(:jido_ui, Jido.UI.LiveView,
      components: JidoUITest.LiveComponents,
      theme: {Jido.UI.LiveView.Theme.DaisyUI, name: "cupcake"}
    )

    html =
      render_component(&Jido.UI.LiveView.surface/1,
        surface: Fixtures.surface()
      )

    assert html =~ ~s(data-theme="cupcake")
    assert html =~ ~s(class="btn btn-primary")
  end

  test "local Theme overrides extend the global Theme without changing routing" do
    html =
      render_component(&Jido.UI.LiveView.surface/1,
        surface: Fixtures.surface(),
        components: JidoUITest.LiveComponents,
        theme: {Jido.UI.LiveView.Theme.DaisyUI, name: "cupcake"},
        theme_overrides: %{
          surface: %{"class" => "compact"},
          regions: %{"worker" => %{"class" => "worker-region"}},
          components: %{"button" => %{"class" => "tracked-action"}},
          nodes: %{
            "workspace" => %{
              "continue" => %{
                "class" => "primary-action",
                "id" => "unsafe-id",
                "phx-click" => "unsafe-event"
              }
            }
          }
        }
      )

    assert html =~ ~s(class="jido-ui compact")
    assert html =~ ~s(class="jido-region worker-region")
    assert html =~ ~s(class="btn btn-primary tracked-action primary-action")
    refute html =~ ~s(id="unsafe-id")
    refute html =~ ~s(phx-click="unsafe-event")
    assert html =~ ~s(phx-click="jido_ui.action")
  end
end

defmodule JidoUITest.LiveComponents do
  @behaviour Jido.UI.LiveView.ComponentSet

  @impl true
  def catalog, do: JidoUITest.Fixtures.catalog()

  @impl true
  def render(assigns), do: Jido.UI.LiveView.Components.Basic.render(assigns)
end
