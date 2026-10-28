defmodule Jido.UI.Builder.Agent do
  @moduledoc "A persistent control point for editable UI drafts and immutable Releases."

  alias Jido.UI.Builder
  alias Jido.UI.Builder.{FreezeFlow, ProposeFlow, State}

  use Jido.Agent,
    name: "jido_ui_builder",
    description: "Designs, validates, freezes, and activates UI Releases"

  state do
    schema(State.schema())
  end

  routes do
    signal_source("/jido/ui/builder")

    route "jido.ui.builder.start", as: :start do
      action input,
        schema: Builder.start_schema(),
        output_schema: State.schema(),
        context: context do
        Builder.begin_build(input, context)
      end
    end

    route("jido.ui.builder.propose", ProposeFlow, as: :propose)
    route("jido.ui.builder.freeze", FreezeFlow, as: :freeze)

    route "jido.ui.builder.activate", as: :activate do
      action input,
        schema: Builder.activate_schema(),
        output_schema: State.schema(),
        context: context do
        Builder.activate_release(input, context)
      end
    end
  end
end
