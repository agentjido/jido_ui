defmodule Jido.UI.Catalog.Basic do
  @moduledoc "A small component Catalog for examples and fallback renderers."

  alias Jido.UI.Catalog

  @doc "Returns the built-in Catalog."
  @spec catalog() :: Catalog.t()
  def catalog do
    Catalog.new!("jido.ui.basic/v1", components(), capabilities())
  end

  defp components do
    %{
      "stack" =>
        Zoi.object(%{
          "gap" => Zoi.enum(["small", "medium", "large"]) |> Zoi.default("medium")
        }),
      "action_bar" => Zoi.object(%{}),
      "heading" =>
        Zoi.object(%{
          "text" => Zoi.string(),
          "level" => Zoi.integer() |> Zoi.min(1) |> Zoi.max(6) |> Zoi.default(2)
        }),
      "text" =>
        Zoi.object(%{
          "text" => Zoi.string(),
          "tone" => Zoi.string() |> Zoi.default("default")
        }),
      "button" =>
        Zoi.object(%{
          "label" => Zoi.string(),
          "variant" => Zoi.string() |> Zoi.default("secondary")
        }),
      "choice_group" =>
        Zoi.object(%{
          "legend" => Zoi.string(),
          "name" => Zoi.string(),
          "options" => Zoi.list(Zoi.object(%{"label" => Zoi.string(), "value" => Zoi.string()}))
        }),
      "notice" =>
        Zoi.object(%{
          "title" => Zoi.string() |> Zoi.optional(),
          "text" => Zoi.string(),
          "tone" => Zoi.string() |> Zoi.default("default")
        }),
      "key_value" =>
        Zoi.object(%{
          "entries" => Zoi.list(Zoi.object(%{"label" => Zoi.string(), "value" => Zoi.string()}))
        })
    }
  end

  defp capabilities do
    %{
      "ui.inspect" => %{
        id: "ui.inspect",
        event: "ui.inspect",
        accepts: [],
        risk: :local
      }
    }
  end
end
