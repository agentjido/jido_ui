example_dir = Path.expand("../../examples/lifecycle", __DIR__)

for file <- ["catalog.exs", "events.exs", "runtime.exs"] do
  Code.require_file(Path.join(example_dir, file))
end

defmodule JidoUI.LifecycleExampleTest do
  use ExUnit.Case, async: false

  alias JidoUI.Examples.Lifecycle.Example

  test "builds, repairs, freezes, persists, activates, and routes one UI" do
    result = Example.run()

    assert result.rejected.state.status == "invalid"
    assert result.builder.state.status == "frozen"
    assert result.builder.state.proposal_revision == 2
    assert result.builder.state.active_release_id == result.release.id
    assert result.persisted_builder_revision >= 5

    assert result.initial_text =~ "Warming the bowl"
    assert result.next_text =~ "Opening the leaves"

    assert {:error, %Jido.UI.Error{code: :stale_region}} = result.stale_interaction_result

    event_types = Enum.map(result.events, & &1.type)

    assert "jido.ui.builder.candidate.rejected" in event_types
    assert "jido.ui.builder.candidate.validated" in event_types
    assert "jido.ui.builder.release.frozen" in event_types
    assert "jido.ui.builder.release.stored" in event_types
    assert "jido.ui.builder.release.activated" in event_types
    assert "jido.ui.lifecycle.runtime.interaction_routed" in event_types
    assert "jido.ui.lifecycle.runtime.state_changed" in event_types
  end
end
