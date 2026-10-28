# Jido UI Repository Guide

Use ASD-STE100 Simplified Technical English. Do not use skills unless requested.

## Scope

`jido_ui` owns renderer-independent Surface data, agent-owned Regions, catalog
validation, UI interaction values, serialization, and renderer adapters. It
does not own domain state, agent execution, durable orchestration, or the
Signal envelope.

## Contract rules

- Keep `Jido.UI.Surface` portable and independent from Phoenix.
- Treat one Agent as the state boundary for one Region.
- A Surface can compose Regions from one root Agent topology.
- Route a Region action to its owning `Jido.Agent.Ref`.
- Keep renderer-specific values inside renderer namespaces.
- Use stable string IDs for surfaces, nodes, actions, and catalog components.
- Validate package-owned boundaries with Zoi.
- Do not create atoms from runtime Surface data.
- Keep browser-only state, such as focus and animation progress, out of a Surface.
- A UI interaction carries user input. The receiving Action must validate it.
- Add protocol adapters at the package edge. Do not make an external protocol
  the internal Surface model.

## Checks

Run these commands from the package root:

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix quality
```
