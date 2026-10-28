defmodule Jido.UI.Builder.FreezeFlow do
  @moduledoc "Freezes and stores one valid Release in one Agent turn."

  alias Jido.UI.Builder
  alias Jido.UI.Builder.State

  use Jido.Flow,
    name: "jido_ui_builder_freeze",
    schema: Builder.freeze_schema(),
    output_schema: State.schema()

  flow do
    step "freeze", metadata <- input(:metadata), inline: [context: context] do
      Builder.freeze_release(metadata, context)
    end

    step "store", state <- result("freeze", :state), inline: [context: context] do
      Builder.store_release(state, context)
    end

    output(result("store", :state))
  end
end
