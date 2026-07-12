defmodule Lotus.Web.Markdown do
  @moduledoc false

  @spec to_safe_html(term()) :: Phoenix.HTML.safe() | String.t()
  def to_safe_html(text) when is_binary(text) and text != "" do
    case MDEx.to_html(text) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      {:error, _} -> text
    end
  end

  def to_safe_html(_), do: ""
end
