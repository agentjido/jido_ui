defmodule Jido.UI.Builder.State do
  @moduledoc "The persistent state owned by one UI Builder Agent."

  alias Jido.UI.Release

  @statuses ["idle", "drafting", "invalid", "valid", "frozen"]

  @schema Zoi.object(
            %{
              status: Zoi.enum(@statuses) |> Zoi.default("idle"),
              build: Zoi.map() |> Zoi.default(%{}),
              proposal_revision: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
              draft: Zoi.map() |> Zoi.default(%{}),
              definition: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil),
              diagnostics: Zoi.list(Zoi.map()) |> Zoi.default([]),
              release: Zoi.struct(Release) |> Zoi.nullable() |> Zoi.default(nil),
              releases:
                Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.struct(Release)) |> Zoi.default(%{}),
              active_release_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
            },
            unrecognized_keys: :error
          )

  @doc "Returns the Builder Agent state schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Returns the supported draft lifecycle states."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end
