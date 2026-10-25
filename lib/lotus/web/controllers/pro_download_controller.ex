defmodule Lotus.Web.ProDownloadController do
  @moduledoc """
  A file Lotus Pro makes for a page of its own, such as the audit log's
  CSV: `GET /pro/download?token=…`.

  A Pro page signs the request with `Lotus.Web.Pro.download_path/3`; the
  route resolves the user as the CSV export does, and Lotus Pro answers
  `Lotus.Web.Pro.download/3` as that user, so the token says what to make,
  never who may have it.
  """

  use Phoenix.Controller, formats: []

  alias Lotus.Web.{Actor, Pro, Resolver}

  plug(:fetch_query_params)

  @doc false
  def download(conn, %{"token" => token}) do
    endpoint = Phoenix.Controller.endpoint_module(conn)

    case Pro.verify_download(endpoint, token) do
      {:ok, name, params} ->
        send_file_of(conn, name, params)

      {:error, :expired} ->
        refuse(conn, :unauthorized, "This download link has expired. Please try again.")

      {:error, _invalid} ->
        refuse(conn, :unauthorized, "Invalid download link.")
    end
  end

  def download(conn, _params), do: refuse(conn, :bad_request, "Missing download token.")

  defp send_file_of(conn, name, params) do
    resolver = conn.private[:lotus_resolver]
    user = Resolver.call_with_fallback(resolver, :resolve_user, [conn])
    {context, scope} = Actor.resolve(resolver, user)
    info = %{user: user, context: context, scope: scope, params: params}

    case Pro.download(name, params, info) do
      {:ok, %{filename: filename, content_type: content_type, body: body}} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{safe(filename)}"))
        |> send_resp(200, body)

      {:error, :forbidden} ->
        refuse(conn, :forbidden, "You don't have permission to download this.")

      _unknown ->
        refuse(conn, :not_found, "Not found.")
    end
  end

  defp refuse(conn, status, message), do: conn |> put_status(status) |> text(message)

  # Nothing that breaks out of the quoted filename or the header.
  defp safe(filename) when is_binary(filename) do
    case filename |> String.replace(~r/[\x00-\x1f\x7f"\\]/, "") |> String.trim() do
      "" -> "download"
      safe -> safe
    end
  end

  defp safe(_filename), do: "download"
end
