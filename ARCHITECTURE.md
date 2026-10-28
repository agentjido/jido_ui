# Jido UI architecture

Jido UI has one canonical model and several adapters. The module DSL, maps,
and JSON all produce a `Jido.UI.Definition`. Renderers consume a complete
`Jido.UI.Surface`.

```text
Spark DSL ─┐
Map ───────┼─> Definition -> Builder -> Release -> Projection
JSON ──────┘                  Agent state               |
                                                        v
                          Renderer <- Surface <- Region
                                               Agent commit
```

## APEX mapping

Jido UI uses the useful APEX split between editable metadata and stable
runtime artifacts. It does not put application logic in a database.

| APEX concept | Jido UI concept |
| --- | --- |
| Application Builder repository | Persistent `Jido.UI.Builder.Agent` state |
| Application | `application_id` |
| Page metadata | `Jido.UI.Definition` draft |
| Shared Components | Trusted `Jido.UI.Catalog` |
| Export or deployment | Immutable `Jido.UI.Release` |
| Session state | Domain Agent state |
| Show Page | Release to Projection to Region to Surface |
| Accept Page | Interaction to Signal to Agent transition |

The Builder Agent is the control point. A Jidoka harness can call a model and
submit a complete candidate. The Builder validates the candidate, keeps repair
diagnostics, freezes valid content, stores releases, and moves the active
release pointer. The harness packet includes a JSON Schema for the complete
candidate. A renderer never sees an editable draft.

## Persistence boundary

`jido_ui` uses normal Jido Agent persistence. It does not depend on Ash or
select a storage system. A host can use `AshJido.Persistence.Adapter` for the
Builder Agent. This stores the complete Builder state and its releases through
the existing Jido persistence contract. Ash-specific Resource and Domain code
stays in `ash_jido`.

`Jido.UI.Release.encode/1` and `decode/1` are the direct database and message
boundary. The wire document has string keys, exact fields, a deterministic
content digest, and the digest of the exact Catalog used at freeze time.

## Package rules

1. The five main values stay at the `Jido.UI` level: `Definition`,
   `Projection`, `Region`, `Surface`, and `Interaction`.
2. A support module lives below the value or adapter that owns it.
3. The Spark DSL is a compile-time input adapter. It is not the canonical
   model.
4. Definitions contain no LiveView classes, Agent references, or Signal
   types.
5. A Catalog is trusted application data. Authored Intent values refer to
   stable capability IDs only.
6. A Region gets its Agent reference and revision only after an Agent state
   commit.

## Module roles

### Core values

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI` | Public facade for define, project, instantiate, validate, bind, and route | Keep small. Delegate Region construction. |
| `Jido.UI.Definition` | Canonical authored graph and graph validation | Keep as the only DSL, Map, and JSON target. |
| `Jido.UI.Node` | One semantic component in a Definition | Keep independent of renderers. |
| `Jido.UI.Child` | A reference to a local Node or child Region | Keep as a small value. |
| `Jido.UI.Intent` | An authored capability reference | Keep separate from resolved Region actions. |
| `Jido.UI.Binding` | Portable JSON Pointer binding and resolver | Keep as data syntax, not executable code. |
| `Jido.UI.Projection` | A Definition plus projected Agent data | Keep free of owner and revision data. |
| `Jido.UI.Region` | A committed Projection with one Agent owner and revision | Keep as the Agent state boundary. |
| `Jido.UI.Surface` | A connected topology of Regions | Keep as the renderer input. |
| `Jido.UI.Interaction` | A revision-aware user event and Signal router | Keep as the interaction boundary. |

### Trusted catalog

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.Catalog` | Trusted component schemas, capability lookup, validation, and content identity | Keep validation with the Catalog because it needs trusted schemas. Export only portable Catalog documents. |
| `Jido.UI.Catalog.Capability` | Stable capability ID to Signal mapping | Nest under Catalog. |
| `Jido.UI.Catalog.Basic` | Small built-in catalog for examples and fallback rendering | Nest under Catalog. Do not treat it as a full design system. |

### Production and Agent boundary

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.Projection.Flow` | Optional default Flow that produces a Projection | Keep one file. Use inline Flow steps instead of wrapper Action modules. |
| `Jido.UI.Region.Builder` | Binds data and resolves Intent values after commit | Internal. Nest under Region. |
| `Jido.UI.Region.Action` | Resolved interaction route stored in a Region | Nest under Region to avoid confusion with `Jido.Action`. |
| `Jido.UI.Agent.Projector` | Adapter from an Agent instance to a committed Region | Nest under Agent integration. |

### Authoring

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.DSL` | Spark DSL entry point and generated module API | Internal authoring front end. |
| `Jido.UI.DSL.Extension` | Spark section and entity schema | Internal. Own only compile-time syntax. |
| `Jido.UI.DSL.Node` | Spark draft Node | Internal. Lower to `Jido.UI.Node`. |
| `Jido.UI.DSL.Intent` | Spark draft Intent | Internal. Lower to `Jido.UI.Intent`. |
| `Jido.UI.DSL.Helpers` | Portable `bind/1` and `region/1` value helpers | Internal. These are values, not declarations. |
| `Jido.UI.DSL.Compiler` | Lowers Spark entities through `Jido.UI.define/2` | Internal. Do not add a second validation path. |
| `Jido.UI.Authoring.Codec` | Jido Authoring document codec | Keep isolated from the core model. |

### Builder and release

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.Builder.Agent` | Persistent owner of one editable build and its release set | Keep model calls outside this Agent. |
| `Jido.UI.Builder` | Signals, trusted Catalog context, and harness packet boundary | Keep it renderer-independent and JSON-safe. |
| `Jido.UI.Builder.ProposeFlow` | Records and validates one complete candidate | Keep proposal validation in one Agent turn. |
| `Jido.UI.Builder.FreezeFlow` | Freezes and stores one valid release | Keep freeze and store in one Agent turn. |
| `Jido.UI.Builder.State` | Draft status, diagnostics, releases, and active pointer | Persist through normal Jido Agent persistence. |
| `Jido.UI.Release` | Content-verified immutable Definition and Catalog artifact | Use its strict wire format at storage boundaries. Never mutate a release. |

### Rendering

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.Renderer` | Contract for value renderers | Keep for text and future protocol renderers. |
| `Jido.UI.Renderer.Text` | Plain-text fallback renderer | Keep small and deterministic. |
| `Jido.UI.LiveView` | LiveView Surface traversal and event attributes | Keep all Phoenix-specific work in this namespace. |
| `Jido.UI.LiveView.ComponentSet` | Semantic component-to-HEEx contract | Keep separate from Theme. |
| `Jido.UI.LiveView.Components.Basic` | Built-in accessible HEEx component set | Nest under LiveView components. |
| `Jido.UI.LiveView.Theme` | Global Theme selection and local override merge | Keep interaction attributes protected. |
| `Jido.UI.LiveView.Theme.Bare` | No-style Theme | Keep as the stable default. |
| `Jido.UI.LiveView.Theme.DaisyUI` | DaisyUI class adapter | Keep optional and CSS-only. |

### Shared support

| Module | Role | Decision |
| --- | --- | --- |
| `Jido.UI.Error` | Package error value | Keep one error type with codes and paths. |
| `Jido.UI.JSON` | JSON-safe validation, canonical encoding, and digest support | Keep internal. Public wire types own their encoding APIs. |

## Removed spike layers

- The hand-written module-attribute DSL was replaced by Spark.
- `Jido.UI.Actions.Define` and `Jido.UI.Actions.Project` were removed. Inline
  Flow steps now keep the default projection Flow in one file.
- `Jido.UI.LiveView.Catalog` and `Jido.UI.LiveView.BasicCatalog` were removed.
  They duplicated `ComponentSet` and the basic components module.
