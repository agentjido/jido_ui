Mix.install([
  {:jido_ui, path: Path.expand("..", __DIR__)},
  {:phoenix_playground, "~> 0.1.9"}
])

demo_port =
  "JIDO_UI_DEMO_PORT"
  |> System.get_env("4174")
  |> String.to_integer()

defmodule JidoUIDemo.Catalog do
  @moduledoc false
  alias Jido.UI.Catalog
  alias Jido.UI.Catalog.{Basic, Capability}

  def catalog do
    basic = Basic.catalog()

    capabilities = %{
      "tea.advance" => Capability.new!(%{id: "tea.advance", event: "tea.advance", risk: :normal}),
      "tea.refresh" => Capability.new!(%{id: "tea.refresh", event: "tea.refresh", risk: :local})
    }

    Catalog.new!(basic.id, basic.components, capabilities)
  end
end

defmodule JidoUIDemo.RootView do
  @moduledoc false
  use Jido.UI, name: "tea-session", catalog: JidoUIDemo.Catalog

  ui do
    root("root")

    node("root", "stack", children: ["title", "copy", region("brew"), "advance"])
    node("title", "heading", props: %{"text" => bind("/title"), "level" => 1})
    node("copy", "text", props: %{"text" => bind("/copy"), "tone" => "quiet"})

    node("advance", "button",
      props: %{"label" => "Advance session", "variant" => "primary"},
      events: %{"activate" => "advance"}
    )

    intent("advance", capability: "tea.advance")
  end
end

defmodule JidoUIDemo.BrewView do
  @moduledoc false
  use Jido.UI, name: "brew-status", catalog: JidoUIDemo.Catalog

  ui do
    root("root")
    node("root", "stack", children: ["status", "refresh"])

    node("status", "notice",
      props: %{
        "title" => "Brew agent",
        "text" => bind("/status"),
        "tone" => "positive"
      }
    )

    node("refresh", "button",
      props: %{"label" => "Refresh brew", "variant" => "quiet"},
      events: %{"activate" => "refresh"}
    )

    intent("refresh", capability: "tea.refresh")
  end
end

defmodule JidoUIDemo.Components do
  @moduledoc false
  @behaviour Jido.UI.LiveView.ComponentSet

  @impl true
  def catalog, do: JidoUIDemo.Catalog.catalog()

  @impl true
  def render(assigns), do: Jido.UI.LiveView.Components.Basic.render(assigns)
end

defmodule JidoUIDemo.Theme do
  @moduledoc false
  @behaviour Jido.UI.LiveView.Theme

  @impl true
  def attributes(:surface, _context, _options), do: %{"class" => "tea-theme"}
  def attributes(:region, _context, _options), do: %{"class" => "tea-region"}
  def attributes(component, _context, _options), do: %{"class" => "tea-#{component}"}
end

Application.put_env(:jido_ui, Jido.UI.LiveView,
  components: JidoUIDemo.Components,
  theme: JidoUIDemo.Theme
)

defmodule JidoUIDemo.Factory do
  @moduledoc false

  def surface(root_revision, brew_revision, step) do
    catalog = JidoUIDemo.Catalog.catalog()

    root_projection =
      projection(JidoUIDemo.RootView.definition(), %{
        "title" => "A quieter dynamic interface",
        "copy" => "A Jido Flow produces data. Each Agent keeps its own UI revision."
      })

    brew_projection =
      projection(JidoUIDemo.BrewView.definition(), %{
        "status" => brew_status(step)
      })

    root =
      Jido.UI.instantiate!(root_projection,
        id: "session",
        owner: Jido.Agent.Ref.new!(namespace: "demo/tea", id: "session-agent"),
        revision: root_revision,
        catalog: catalog
      )

    brew =
      Jido.UI.instantiate!(brew_projection,
        id: "brew",
        owner: Jido.Agent.Ref.new!(namespace: "demo/tea", id: "brew-agent"),
        revision: brew_revision,
        catalog: catalog
      )

    Jido.UI.Surface.compose!("tea-onboarding", root, [brew], metadata: %{"step" => step})
  end

  defp projection(definition, data) do
    {:ok, %{projection: projection}} =
      Jido.Exec.run(Jido.UI.Projection.Flow, %{definition: definition, data: data})

    projection
  end

  defp brew_status(step) do
    Enum.at(["Warming the bowl", "Opening the leaves", "Ready to pour"], rem(step, 3))
  end
end

defmodule JidoUIDemo.Live do
  @moduledoc false
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_state(socket, 1, 1, 0, "No interaction yet")}
  end

  @impl true
  def handle_event("jido_ui.action", params, socket) do
    with {:ok, interaction} <- Jido.UI.Interaction.from_params(params),
         {:ok, owner, signal} <- Jido.UI.route(interaction, socket.assigns.surface) do
      {root_revision, brew_revision, step} = next_state(signal.type, socket.assigns)

      message =
        "#{owner.id} received #{signal.type} at region revision #{interaction.region_revision}"

      {:noreply, assign_state(socket, root_revision, brew_revision, step, message)}
    else
      {:error, error} -> {:noreply, assign(socket, :message, Exception.message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      :root {
        --paper: #f6f0e5;
        --ink: #172321;
        --muted: #60706b;
        --plum: #6a376d;
        --plum-deep: #432247;
        --line: #cfc4b3;
        color-scheme: light;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-width: 320px;
        background:
          radial-gradient(circle at 78% 14%, rgba(106, 55, 109, .11), transparent 27rem),
          var(--paper);
        color: var(--ink);
        font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      button { font: inherit; }
      .shell { width: min(1040px, calc(100% - 36px)); margin: 0 auto; padding: 52px 0 80px; }
      .masthead { display: grid; grid-template-columns: 1fr auto; gap: 32px; align-items: end; border-bottom: 1px solid var(--ink); padding-bottom: 24px; }
      .eyebrow { margin: 0 0 10px; color: var(--plum); font: 700 12px/1.2 ui-monospace, monospace; letter-spacing: .14em; text-transform: uppercase; }
      h1 { margin: 0; max-width: 720px; font: 400 clamp(44px, 7vw, 78px)/.94 Georgia, serif; letter-spacing: -.05em; }
      .cup { position: relative; width: 92px; height: 72px; border-radius: 8px 8px 42px 42px; background: var(--ink); }
      .cup::after { content: ""; position: absolute; right: -27px; top: 12px; width: 34px; height: 34px; border: 9px solid var(--ink); border-left: 0; border-radius: 0 28px 28px 0; }
      .steam, .steam::before { position: absolute; content: ""; width: 14px; height: 42px; border-radius: 50%; border-left: 4px solid var(--plum); top: -50px; left: 32px; animation: rise 2.8s ease-in-out infinite; }
      .steam::before { top: 8px; left: 20px; height: 34px; animation-delay: -.9s; }
      @keyframes rise { 0%, 100% { transform: translateY(5px) rotate(8deg); opacity: .25; } 50% { transform: translateY(-5px) rotate(-8deg); opacity: .9; } }
      .topology { display: flex; gap: 8px; margin: 22px 0 38px; overflow-x: auto; }
      .chip { min-width: 190px; padding: 12px 14px; border: 1px solid var(--line); background: rgba(255,255,255,.32); }
      .chip strong, .chip span { display: block; }
      .chip span { margin-top: 4px; color: var(--muted); font: 12px ui-monospace, monospace; }
      .panel { display: grid; grid-template-columns: 1fr 280px; gap: 28px; padding: 32px; border: 1px solid var(--line); border-radius: 28px; background: rgba(255,255,255,.42); box-shadow: 0 24px 70px rgba(34,28,24,.09); }
      [data-jido-component="stack"] { display: grid; gap: 20px; }
      [data-jido-component="heading"] { margin: 0; font: 400 clamp(32px, 5vw, 56px)/1 Georgia, serif; letter-spacing: -.035em; }
      [data-jido-component="text"] { margin: 0; max-width: 620px; color: var(--muted); line-height: 1.65; }
      .tea-region--brew { padding: 20px; border-left: 3px solid var(--plum); background: #eee4d5; }
      [data-jido-component="notice"] strong { display: block; margin-bottom: 7px; }
      [data-jido-component="notice"] p { margin: 0; color: var(--muted); }
      [data-jido-component="button"] { width: fit-content; border: 0; border-radius: 999px; padding: 11px 18px; color: #fff; background: var(--plum-deep); cursor: pointer; }
      .tea-button--advance { box-shadow: 0 8px 24px rgba(67, 34, 71, .2); }
      .event-log { padding: 18px; border: 1px solid var(--line); font: 12px/1.6 ui-monospace, monospace; color: var(--muted); }
      .event-log strong { display: block; color: var(--ink); margin-bottom: 6px; }
      @media (max-width: 760px) { .masthead, .panel { grid-template-columns: 1fr; } .cup { display: none; } }
      @media (prefers-reduced-motion: reduce) { .steam, .steam::before { animation: none; } }
    </style>

    <main class="shell">
      <header class="masthead">
        <div>
          <p class="eyebrow">Definition → Flow → Projection → Region</p>
          <h1>One surface. Two Agent boundaries.</h1>
        </div>
        <div class="cup" aria-hidden="true"><span class="steam"></span></div>
      </header>

      <div class="topology" aria-label="Agent topology">
        <div class="chip"><strong>Session Agent</strong><span>revision {@root_revision}</span></div>
        <div class="chip"><strong>Brew Agent</strong><span>revision {@brew_revision}</span></div>
      </div>

      <section class="panel">
        <Jido.UI.LiveView.surface
          surface={@surface}
          theme_overrides={
            %{
              regions: %{"brew" => %{"class" => "tea-region--brew"}},
              nodes: %{
                "session" => %{"advance" => %{"class" => "tea-button--advance"}}
              }
            }
          }
        />
        <aside class="event-log"><strong>Last routed Signal</strong>{@message}</aside>
      </section>
    </main>
    """
  end

  defp next_state("tea.advance", assigns) do
    {assigns.root_revision + 1, assigns.brew_revision, assigns.step + 1}
  end

  defp next_state("tea.refresh", assigns) do
    {assigns.root_revision, assigns.brew_revision + 1, assigns.step + 1}
  end

  defp assign_state(socket, root_revision, brew_revision, step, message) do
    assign(socket,
      page_title: "Jido UI projection spike",
      root_revision: root_revision,
      brew_revision: brew_revision,
      step: step,
      message: message,
      surface: JidoUIDemo.Factory.surface(root_revision, brew_revision, step)
    )
  end
end

PhoenixPlayground.start(
  live: JidoUIDemo.Live,
  port: demo_port,
  endpoint_options: [check_origin: false],
  open_browser: false
)
