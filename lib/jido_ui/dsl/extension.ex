defmodule Jido.UI.DSL.Node do
  @moduledoc false
  defstruct [
    :id,
    :component,
    :__identifier__,
    :__spark_metadata__,
    props: %{},
    children: [],
    events: %{}
  ]
end

defmodule Jido.UI.DSL.Intent do
  @moduledoc false
  defstruct [:id, :capability, :__identifier__, :__spark_metadata__, input: %{}]
end

defmodule Jido.UI.DSL.Extension do
  @moduledoc false

  @node %Spark.Dsl.Entity{
    name: :node,
    target: Jido.UI.DSL.Node,
    args: [:id, :component],
    identifier: :id,
    describe: "Declares one catalog component Node.",
    schema: [
      id: [type: :string, required: true],
      component: [type: :string, required: true],
      props: [type: {:map, :any, :any}, default: %{}],
      children: [type: {:list, :any}, default: []],
      events: [type: {:map, :any, :any}, default: %{}]
    ]
  }

  @intent %Spark.Dsl.Entity{
    name: :intent,
    target: Jido.UI.DSL.Intent,
    args: [:id],
    identifier: :id,
    describe: "Declares one reference to a trusted Catalog capability.",
    schema: [
      id: [type: :string, required: true],
      capability: [type: :string, required: true],
      input: [type: {:map, :any, :any}, default: %{}]
    ]
  }

  @ui %Spark.Dsl.Section{
    name: :ui,
    describe: "Declares one renderer-independent UI Definition.",
    imports: [Jido.UI.DSL.Helpers],
    schema: [
      root: [type: :string, required: true, doc: "The root Node ID."]
    ],
    entities: [@node, @intent]
  }

  use Spark.Dsl.Extension, sections: [@ui]
end
