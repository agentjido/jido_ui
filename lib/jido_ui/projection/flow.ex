defmodule Jido.UI.Projection.Flow do
  @moduledoc """
  The default Flow for Definition normalization and UI Projection.

  Applications can use this Flow as-is or author a larger Flow that produces a
  `Jido.UI.Projection` at its own boundary.
  """

  use Jido.Flow,
    name: "jido_ui_projection",
    description: "Normalizes a UI Definition and projects Agent data",
    schema:
      Zoi.object(%{
        definition: Zoi.any(),
        data: Zoi.map() |> Zoi.default(%{}),
        status: Zoi.enum([:ready, :busy, :waiting, :complete, :error]) |> Zoi.default(:ready),
        metadata: Zoi.map() |> Zoi.default(%{})
      }),
    output_schema: Zoi.object(%{projection: Zoi.any()})

  flow do
    step "define", definition <- input(:definition) do
      case Jido.UI.Definition.new(definition) do
        {:ok, definition} -> {:ok, %{definition: definition}}
        {:error, error} -> {:error, error}
      end
    end

    step "project",
         [
           definition <- result("define", :definition),
           data <- input(:data),
           status <- input(:status),
           metadata <- input(:metadata)
         ] do
      case Jido.UI.project(definition, data, status: status, metadata: metadata) do
        {:ok, projection} -> {:ok, %{projection: projection}}
        {:error, error} -> {:error, error}
      end
    end

    output(result("project"))
  end
end
