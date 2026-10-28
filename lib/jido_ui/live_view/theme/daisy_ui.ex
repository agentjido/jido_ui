defmodule Jido.UI.LiveView.Theme.DaisyUI do
  @moduledoc """
  A small DaisyUI class adapter for the built-in component set.

  The host application must install DaisyUI and load its generated CSS. Set
  the DaisyUI theme name with `{__MODULE__, name: "cupcake"}`.
  """

  @behaviour Jido.UI.LiveView.Theme

  @impl true
  def attributes(:surface, _context, options) do
    %{"class" => "jido-ui", "data-theme" => Keyword.get(options, :name, "light")}
  end

  def attributes(:region, _context, _options), do: %{"class" => "jido-region"}
  def attributes("stack", _context, _options), do: %{"class" => "flex flex-col gap-4"}
  def attributes("action_bar", _context, _options), do: %{"class" => "join flex gap-2"}
  def attributes("heading", _context, _options), do: %{"class" => "text-3xl font-bold"}
  def attributes("text", _context, _options), do: %{"class" => "text-base-content/70"}

  def attributes("button", context, _options) do
    variant = context.node.props["variant"] || "secondary"
    %{"class" => "btn #{button_variant(variant)}"}
  end

  def attributes("choice_group", _context, _options) do
    %{"class" => "fieldset bg-base-200 border-base-300 rounded-box border p-4"}
  end

  def attributes("notice", context, _options) do
    tone = context.node.props["tone"] || "default"
    %{"class" => "alert #{notice_tone(tone)}"}
  end

  def attributes("key_value", _context, _options), do: %{"class" => "stats stats-vertical"}
  def attributes(_element, _context, _options), do: %{}

  defp button_variant("primary"), do: "btn-primary"
  defp button_variant("secondary"), do: "btn-secondary"
  defp button_variant("quiet"), do: "btn-ghost"
  defp button_variant("danger"), do: "btn-error"
  defp button_variant(_variant), do: "btn-secondary"

  defp notice_tone("positive"), do: "alert-success"
  defp notice_tone("warning"), do: "alert-warning"
  defp notice_tone("danger"), do: "alert-error"
  defp notice_tone(_tone), do: "alert-info"
end
