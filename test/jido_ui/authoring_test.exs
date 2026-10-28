defmodule Jido.UI.AuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.UI.{Definition, Projection}
  alias Jido.UI.Authoring.Codec
  alias JidoUITest.Fixtures

  test "Definition JSON uses the shared Jido Authoring entry point" do
    definition = Fixtures.root_definition()
    registry = Jido.Authoring.Registry.new!(%{})

    assert {:ok, document} =
             Jido.Authoring.encode(definition, codec: Codec, registry: registry)

    assert document["type"] == "jido.ui.definition"
    assert document["intents"]["continue"]["capability"] == "workspace.continue"
    refute Map.has_key?(document["intents"]["continue"], "event")

    assert {:ok, decoded} =
             Jido.Authoring.decode(document, codec: Codec, registry: registry)

    assert %Definition{} = decoded
    assert decoded == definition
  end

  test "the default Jido Flow produces a Projection" do
    assert {:ok, %{projection: projection}} =
             Jido.Exec.run(Jido.UI.Projection.Flow, %{
               definition: Fixtures.root_definition(),
               data: %{"title" => "Flow view", "selection" => "remote"}
             })

    assert %Projection{} = projection
    assert projection.data["title"] == "Flow view"
  end
end
