defmodule JidoUI.Examples.Lifecycle.EventRouter do
  @moduledoc false

  use Jido.Signal.Router

  route("jido.ui.builder.release.**", :release)
  route("jido.ui.builder.build.**", :build)
  route("jido.ui.builder.candidate.**", :build)
  route("jido.ui.lifecycle.build.**", :build)
  route("jido.ui.lifecycle.release.**", :release)
  route("jido.ui.lifecycle.runtime.**", :runtime)
end

defmodule JidoUI.Examples.Lifecycle.Events do
  @moduledoc false

  alias Jido.Signal
  alias JidoUI.Examples.Lifecycle.EventRouter

  @source "/examples/jido_ui/lifecycle"

  def directive(stage, data, context) do
    signal = signal(stage, data)
    dispatch = Map.fetch!(context, :lifecycle_dispatch)
    Jido.Agent.Directive.emit(signal, dispatch)
  end

  def dispatch(stage, data, dispatch) do
    stage
    |> signal(data)
    |> Jido.Signal.Dispatch.dispatch(dispatch)
  end

  def drain(timeout \\ 25), do: drain([], timeout)

  defp drain(events, timeout) do
    receive do
      {:signal, %Signal{} = signal} -> drain([classify(signal) | events], timeout)
    after
      timeout -> Enum.reverse(events)
    end
  end

  defp signal(stage, data) do
    Signal.new!("jido.ui.lifecycle.#{stage}", data, source: @source)
  end

  defp classify(signal) do
    {:ok, [category]} = EventRouter.route(signal)

    %{
      category: category,
      type: signal.type,
      data: signal.data
    }
  end
end
