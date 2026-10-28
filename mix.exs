defmodule JidoUI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_ui"
  @description "Renderer-independent dynamic UI surfaces for Jido"

  def project do
    [
      app: :jido_ui,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido UI",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [q: :test, quality: :test]]
  end

  defp deps do
    [
      {:jido, path: "../jido", override: true},
      {:jido_action, path: "../jido_action", override: true},
      {:jido_signal, path: "../jido_signal", override: true},
      {:runic, "~> 0.1.0-alpha.12", override: true},
      {:jason, "~> 1.4"},
      {:spark, "~> 2.7"},
      {:zoi, "~> 0.18.11"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      demo: "cmd elixir examples/demo.exs",
      q: ["quality"],
      quality: ["format --check-formatted", "compile --warnings-as-errors", "test"]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "ARCHITECTURE.md", "LICENSE"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "ARCHITECTURE.md", "LICENSE"],
      skip_undefined_reference_warnings_on: ["ARCHITECTURE.md"],
      groups_for_modules: [
        "Surface Model": [
          Jido.UI,
          Jido.UI.Binding,
          Jido.UI.Catalog,
          Jido.UI.Catalog.Basic,
          Jido.UI.Catalog.Capability,
          Jido.UI.Child,
          Jido.UI.Definition,
          Jido.UI.Intent,
          Jido.UI.Node,
          Jido.UI.Projection,
          Jido.UI.Region,
          Jido.UI.Surface
        ],
        Production: [
          Jido.UI.Agent.Projector,
          Jido.UI.Projection.Flow,
          Jido.UI.Region.Action
        ],
        Interaction: [Jido.UI.Interaction],
        Authoring: [Jido.UI.Authoring.Codec],
        Renderers: [
          Jido.UI.Renderer,
          Jido.UI.Renderer.Text,
          Jido.UI.LiveView,
          Jido.UI.LiveView.ComponentSet,
          Jido.UI.LiveView.Components.Basic,
          Jido.UI.LiveView.Theme,
          Jido.UI.LiveView.Theme.Bare,
          Jido.UI.LiveView.Theme.DaisyUI
        ]
      ]
    ]
  end
end
