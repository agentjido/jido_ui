# Dynamic UI lifecycle spike

Run the example from the `jido_ui` package:

```text
mix lifecycle
```

The example has two Jido Agents:

- `BuilderAgent` runs the authoring Flow. Its persisted state owns the current
  build, immutable releases, and the active-release pointer.
- `TeaAgent` owns domain state. A frozen release projects that state into one
  revisioned Jido UI Region.

The public `Jido.UI.Builder.Agent` owns proposal validation, repair diagnostics,
freeze, persistence, and activation. Signal Dispatch sends lifecycle events to
the example process. Signal Router classifies the events as build, release, or
runtime events.

The first candidate is intentionally invalid. The example harness adds the
missing button label and submits a second proposal. No AI model is used.
