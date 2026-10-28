example_dir = Path.join(__DIR__, "lifecycle")

for file <- ["catalog.exs", "events.exs", "runtime.exs"] do
  Code.require_file(Path.join(example_dir, file))
end

result = JidoUI.Examples.Lifecycle.Example.run()

IO.puts("""

=== frozen release ===
#{result.release.id}
digest: #{result.release.digest}
persisted Builder revision: #{result.persisted_builder_revision}

=== first projection ===
#{result.initial_text}

=== projection after one routed interaction ===
#{result.next_text}

=== lifecycle signals ===
""")

Enum.each(result.events, fn event ->
  IO.puts("#{event.category}: #{event.type}")
end)

case result.stale_interaction_result do
  {:error, error} -> IO.puts("\nstale interaction rejected: #{Exception.message(error)}")
  _other -> IO.puts("\nstale interaction was not rejected")
end
