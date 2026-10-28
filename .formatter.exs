ui_locals = [
  ui: 1,
  root: 1,
  node: 2,
  node: 3,
  intent: 2
]

[
  import_deps: [:phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  locals_without_parens: ui_locals,
  export: [locals_without_parens: ui_locals],
  inputs: ["{mix,.formatter}.exs", "{config,examples,lib,test}/**/*.{ex,exs,heex}"]
]
