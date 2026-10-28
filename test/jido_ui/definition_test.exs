defmodule JidoUITest.DSLView do
  use Jido.UI,
    id: "tests/dsl-view",
    name: "dsl-view",
    catalog: Jido.UI.Catalog.Basic,
    metadata: %{"source" => "spark"}

  ui do
    root("root")

    node("root", "stack", children: ["title", "inspect"])
    node("title", "heading", props: %{"text" => bind("/title"), "level" => 1})

    node("inspect", "button",
      props: %{"label" => "Inspect"},
      events: %{"activate" => "inspect"}
    )

    intent("inspect", capability: "ui.inspect", input: %{"target" => bind("/target")})
  end
end

defmodule Jido.UI.DefinitionTest do
  use ExUnit.Case, async: true

  alias Jido.UI.{Definition, Projection}
  alias JidoUITest.{DSLView, Fixtures}

  test "normalizes map authoring into one canonical Definition" do
    definition = Fixtures.root_definition()

    assert %Definition{name: "workspace"} = definition
    assert definition.nodes["title"].props["text"] == %{"$path" => "/title"}
    assert definition.intents["continue"].capability == "workspace.continue"
  end

  test "normalizes JSON object fields without creating runtime atoms" do
    document = %{
      "name" => "json-view",
      "catalog" => "jido.ui.basic/v1",
      "root" => "root",
      "nodes" => %{
        "root" => %{
          "component" => "stack",
          "children" => [%{"kind" => "node", "id" => "label"}]
        },
        "label" => %{"component" => "text", "props" => %{"text" => "Ready"}}
      }
    }

    assert {:ok, definition} =
             Jido.UI.define(document, catalog: Jido.UI.Catalog.Basic)

    assert definition.name == "json-view"
    assert definition.nodes["root"].children == [Jido.UI.Child.new!("label")]
  end

  test "the DSL lowers to the same canonical value shape" do
    definition = DSLView.definition()

    assert %Definition{name: "dsl-view"} = definition
    assert definition.root == "root"
    assert definition.metadata == %{"source" => "spark"}
    assert definition.nodes["title"].props["text"] == %{"$path" => "/title"}
    assert DSLView.__jido_authoring__().kind == :ui_definition
  end

  test "a Projection has data but no Agent boundary" do
    assert %Projection{} = projection = Fixtures.root_projection()
    refute Map.has_key?(projection, :owner)
    refute Map.has_key?(projection, :revision)
  end

  test "an authored definition cannot select an arbitrary Signal type" do
    attrs = %{
      name: "unsafe",
      catalog: "jido.ui.basic/v1",
      root: "root",
      nodes: %{"root" => %{component: "button", props: %{"label" => "Run"}}},
      intents: %{"run" => %{capability: "system.shell.execute"}}
    }

    assert {:error, %Jido.UI.Error{code: :unknown_capability}} =
             Jido.UI.define(attrs, catalog: Jido.UI.Catalog.Basic)
  end
end
