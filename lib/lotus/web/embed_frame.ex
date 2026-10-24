defmodule Lotus.Web.EmbedFrame do
  @moduledoc """
  A plug for the pipeline of the embed routes (`Lotus.Web.Router.lotus_embed/2`):
  which sites may frame the page.

  It asks Lotus Pro about the route's token (`verify_embed`) and sends
  `content-security-policy: frame-ancestors` with the origins Pro allows for
  it. A token Pro refuses, a route without one, or an app without Pro gets
  `frame-ancestors 'none'`: no site may frame it. It removes
  `x-frame-options`, which `put_secure_browser_headers` sets and which would
  forbid every frame.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      conn
      |> delete_resp_header("x-frame-options")
      |> put_resp_header("content-security-policy", "frame-ancestors " <> ancestors(conn))
    end)
  end

  defp ancestors(conn) do
    with %{"token" => token} <- conn.path_params,
         {:ok, kind} <- kind(conn.path_info),
         {:ok, %{frame_ancestors: [_ | _] = origins}} <-
           Lotus.Web.Pro.verify_embed(token, %{kind: kind, params: conn.params}) do
      Enum.join(origins, " ")
    else
      _ -> "'none'"
    end
  end

  # The route's kind: the segment before the token.
  defp kind(path_info) do
    case Enum.take(path_info, -2) do
      ["dashboard", _token] -> {:ok, :dashboard}
      ["card", _token] -> {:ok, :card}
      _ -> :error
    end
  end
end
