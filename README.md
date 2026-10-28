# Jido UI

Jido UI is a renderer-independent UI system for Jido V3.

It separates authored UI structure from Agent runtime ownership:

```text
DSL | Map | JSON
        |
        v
    Definition
        |
        v
   Jido Flow
        |
        v
    Projection
        |
   Agent commits
        |
        v
      Region  <--- Agent.Ref and revision
        |
        v
      Surface <--- topology of Agent-owned Regions
        |
        +--- LiveView
        +--- text
        +--- future protocol adapters
```

## Main values

- `Jido.UI.Definition` is portable authored structure. It has Nodes, data
  bindings, and stable Intent capability IDs.
- `Jido.UI.Projection` combines a Definition with Agent state. A Flow can
  produce it. It has no Agent reference or revision.
- `Jido.UI.Region` adds the trusted Agent reference and committed revision.
- `Jido.UI.Surface` composes a root Region and child Regions as one view.
- `Jido.UI.Catalog` owns component schemas and maps capability IDs to trusted
  Signal types.

A model can write a Definition or help a Flow produce a Projection. It cannot
select an arbitrary Signal type. Only the trusted Catalog can do this.

## DSL

```elixir
defmodule MyApp.WorkspaceView do
  use Jido.UI,
    id: "views/workspace",
    name: "workspace",
    catalog: MyApp.UICatalog

  ui do
    root "root"

    node "root", "stack", children: ["title", region("worker"), "continue"]
    node "title", "heading", props: %{"text" => bind("/title"), "level" => 1}

    node "continue", "button",
      props: %{"label" => "Continue"},
      events: %{"activate" => "continue"}

    intent "continue",
      capability: "workspace.continue",
      input: %{"mode" => bind("/mode")}
  end
end
```

The DSL returns the same `Jido.UI.Definition` value as Map and JSON authoring:

```elixir
definition = MyApp.WorkspaceView.definition()
```

## Map and JSON

```elixir
{:ok, definition} =
  Jido.UI.define(
    %{
      name: "status",
      catalog: "jido.ui.basic/v1",
      root: "root",
      nodes: %{
        "root" => %{
          component: "text",
          props: %{"text" => Jido.UI.bind("/status")}
        }
      }
    },
    catalog: Jido.UI.Catalog.Basic
  )

registry = Jido.Authoring.Registry.new!(%{})

{:ok, document} =
  Jido.Authoring.encode(definition,
    codec: Jido.UI.Authoring.Codec,
    registry: registry
  )
```

Applications can register `Jido.UI.Authoring.Codec` through normal Jido discovery.

## Flow production

The default Flow normalizes the Definition and produces a Projection:

```elixir
{:ok, %{projection: projection}} =
  Jido.Exec.run(Jido.UI.Projection.Flow, %{
    definition: definition,
    data: %{"status" => "Ready"}
  })
```

An application can replace this Flow with a domain Flow. A model call can be
one Action in that Flow. Rendering does not run the Flow.

## Agent boundary and topology

Add the trusted runtime boundary only after the Agent state commit:

```elixir
region =
  Jido.UI.instantiate!(projection,
    id: "workspace",
    owner: agent_ref,
    revision: committed_revision,
    catalog: MyApp.UICatalog
  )

surface =
  Jido.UI.Surface.compose!(
    "workspace-screen",
    region,
    child_regions
  )
```

Each Region keeps its own owner and revision. The Surface does not copy a root
owner or root revision.

## Rendering and interactions

LiveView keeps three concepts separate:

- `Jido.UI.Catalog` defines semantic component properties and trusted actions.
- `Jido.UI.LiveView.ComponentSet` maps those semantic components to HEEx markup.
- `Jido.UI.LiveView.Theme` adds trusted classes and presentation attributes.

This means a theme cannot change interaction routing or the authored UI data.
A ComponentSet can use the same Theme with different Catalog capabilities.

Set the application-wide LiveView defaults in configuration:

```elixir
config :jido_ui, Jido.UI.LiveView,
  components: MyApp.LiveComponents,
  theme: MyApp.Theme
```

```elixir
{:ok, text} =
  Jido.UI.Renderer.Text.render(surface, catalog: MyApp.UICatalog.catalog())
```

```heex
<Jido.UI.LiveView.surface
  surface={@surface}
  theme_overrides={%{
    regions: %{"brew" => %{"class" => "warm-panel"}},
    nodes: %{"brew" => %{"refresh" => %{"class" => "quiet-action"}}}
  }}
/>
```

The configured `theme` is the global Theme selection. A surface can still pass
`theme` or `components` to replace a default. `theme_overrides` adds
presentation attributes to the surface, a Region, a component type, or one
Node. Local classes extend the global classes. Renderer-owned IDs and event
attributes remain protected.

The built-in DaisyUI adapter emits DaisyUI and Tailwind classes. The host
application must install DaisyUI and load its CSS:

```heex
<Jido.UI.LiveView.surface
  surface={@surface}
  components={MyApp.LiveComponents}
  theme={{Jido.UI.LiveView.Theme.DaisyUI, name: "cupcake"}}
/>
```

A ComponentSet declares the renderer-independent Catalog that it implements:

```elixir
defmodule MyApp.LiveComponents do
  @behaviour Jido.UI.LiveView.ComponentSet

  def catalog, do: MyApp.UICatalog.catalog()

  def render(assigns) do
    Jido.UI.LiveView.Components.Basic.render(assigns)
  end
end
```

The module DSL uses Spark. Spark validates declarations and keeps source
metadata. Its internal compiler lowers Spark entities through the same
`Jido.UI.define/2` path used by maps and JSON.

`Jido.UI.Interaction.route/3` checks the selected Region revision. It returns
the Region owner and a Signal that uses the trusted Catalog event.

## Local development

```sh
mix deps.get
mix quality
mix demo
# or run the standalone file directly
elixir examples/demo.exs
```

The demo uses Phoenix Playground and listens on `http://127.0.0.1:4174` by
default.

See [ARCHITECTURE.md](ARCHITECTURE.md) for package boundaries and module roles.
