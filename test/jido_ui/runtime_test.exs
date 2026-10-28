defmodule Jido.UI.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.UI.{Catalog, Interaction, Surface}
  alias Jido.UI.Agent.Projector
  alias JidoUITest.Fixtures

  test "instantiation binds data and adds the committed Agent boundary" do
    region = Fixtures.root_region()

    assert region.owner == Fixtures.root_owner()
    assert region.revision == 7
    assert region.nodes["title"].props["text"] == "Agent workspace"
    assert region.actions["continue"].event == "workspace.continue"
    assert region.actions["continue"].input == %{"mode" => "local"}
  end

  test "a Surface composes Regions from separate Agent boundaries" do
    surface = Fixtures.surface()

    assert surface.regions["workspace"].owner == Fixtures.root_owner()
    assert surface.regions["worker"].owner == Fixtures.child_owner()
    assert surface.regions["worker"].revision == 3
    refute Map.has_key?(surface, :revision)
    assert {:ok, ^surface} = Surface.validate(surface)
    assert {:ok, ^surface} = Catalog.validate_surface(Fixtures.catalog(), surface)
  end

  test "an interaction routes to the Region owner and trusted Signal" do
    interaction =
      Interaction.new!(%{
        surface_id: "agent-workspace",
        region_id: "workspace",
        region_revision: 7,
        action_id: "continue",
        values: %{"note" => "Ready"}
      })

    assert {:ok, owner, signal} = Interaction.route(interaction, Fixtures.surface())
    assert owner == Fixtures.root_owner()
    assert signal.type == "workspace.continue"
    assert signal.data["input"] == %{"mode" => "local", "note" => "Ready"}
  end

  test "a stale Region interaction is rejected" do
    interaction =
      Interaction.new!(%{
        surface_id: "agent-workspace",
        region_id: "worker",
        region_revision: 2,
        action_id: "refresh"
      })

    assert {:error, %Jido.UI.Error{code: :stale_region}} =
             Interaction.route(interaction, Fixtures.surface())
  end

  test "browser values cannot replace trusted Action input" do
    surface = Fixtures.surface()
    region = surface.regions["workspace"]
    action = region.actions["continue"]
    action = %{action | accepts: ["mode", "note"]}
    region = %{region | actions: Map.put(region.actions, action.id, action)}
    surface = %{surface | regions: Map.put(surface.regions, region.id, region)}

    interaction =
      Interaction.new!(%{
        surface_id: "agent-workspace",
        region_id: "workspace",
        region_revision: 7,
        action_id: "continue",
        values: %{"mode" => "browser"}
      })

    assert {:error, %Jido.UI.Error{code: :protected_values}} =
             Interaction.route(interaction, surface)
  end

  test "a Projector cannot choose the trusted owner or revision" do
    agent = JidoUITest.Agent.instantiate!(id: "workspace-1")

    assert {:ok, region} =
             Projector.project(
               JidoUITest.Projector,
               agent,
               Fixtures.root_owner(),
               9,
               catalog: Fixtures.catalog()
             )

    assert region.owner == Fixtures.root_owner()
    assert region.revision == 9
    assert region.nodes["root"].props["text"] == "Test"
  end
end
