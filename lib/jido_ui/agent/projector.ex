defmodule Jido.UI.Agent.Projector do
  @moduledoc "Projects Agent state, then adds its trusted committed boundary."

  alias Jido.UI.{Error, Projection, Region}

  @callback project(Jido.Agent.instance(), map()) ::
              {:ok, Projection.t()} | {:error, term()}

  @doc "Runs a Projector and makes its Agent-owned Region."
  @spec project(module(), Jido.Agent.instance(), Jido.Agent.Ref.t(), non_neg_integer(), keyword()) ::
          {:ok, Region.t()} | {:error, term()}
  def project(module, %Jido.Agent{} = agent, %Jido.Agent.Ref{} = owner, revision, opts \\ [])
      when is_atom(module) and is_integer(revision) and revision >= 0 and is_list(opts) do
    context = Keyword.get(opts, :context, %{})

    with {:ok, %Projection{} = projection} <- module.project(agent, context),
         {:ok, projection} <- Projection.validate(projection) do
      Jido.UI.instantiate(projection,
        owner: owner,
        revision: revision,
        id: Keyword.get(opts, :id, projection.definition.name),
        catalog: Keyword.get(opts, :catalog)
      )
    else
      {:ok, value} ->
        {:error,
         Error.new(:invalid_projection, "Projector did not return a Projection",
           details: %{value: value}
         )}

      {:error, _reason} = error ->
        error
    end
  end
end
