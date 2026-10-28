defmodule Jido.UI.Builder.ProposeFlow do
  @moduledoc "Records and validates one complete Builder candidate in one Agent turn."

  alias Jido.UI.Builder
  alias Jido.UI.Builder.State

  use Jido.Flow,
    name: "jido_ui_builder_propose",
    schema: Builder.propose_schema(),
    output_schema: State.schema()

  flow do
    step "record", candidate <- input(:candidate), inline: [context: context] do
      Builder.record_draft(candidate, context)
    end

    step "validate", state <- result("record", :state), inline: [context: context] do
      Builder.validate_draft(state, context)
    end

    output(result("validate", :state))
  end
end
