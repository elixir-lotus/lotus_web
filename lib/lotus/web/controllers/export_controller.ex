defmodule Lotus.Web.ExportController do
  @moduledoc """
  Controller for streaming CSV exports.
  """

  use Phoenix.Controller, formats: [:csv]

  alias Lotus.Export
  alias Lotus.Web.Actor
  alias Lotus.Web.Resolver
  alias Lotus.Storage.Query

  plug(:fetch_query_params)

  @max_age 300
  @token_salt "lotus_export"

  @doc """
  Streams a CSV export directly to the response.

  Expects a signed token containing:
  - query_id: ID of the query to export
  - repo: data repository name
  - vars: variable values
  - search_path: optional search path
  - filename: suggested filename for download
  """
  def csv(conn, %{"token" => token}) do
    endpoint = Phoenix.Controller.endpoint_module(conn)

    case Phoenix.Token.decrypt(endpoint, @token_salt, token, max_age: @max_age) do
      {:ok, export_params} ->
        stream_csv_export(conn, export_params)

      {:error, :expired} ->
        conn
        |> put_status(:unauthorized)
        |> text("Export link has expired. Please try again")

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> text("Invalid export token")
    end
  end

  def csv(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> text("Missing export token.")
  end

  defp stream_csv_export(conn, export_params) do
    case build_query(export_params) do
      %Query{} = query ->
        filename =
          export_params
          |> Map.get("filename", "export.csv")
          |> sanitize_filename()

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_chunked(200)
        |> stream_chunks(query, export_params)

      nil ->
        conn
        |> put_status(:not_found)
        |> text("Query not found.")
    end
  end

  # Sanitize filename to prevent Content-Disposition header injection.
  # Strips characters that could break out of the quoted filename or inject
  # additional headers (double quotes, backslashes, CR/LF, control chars).
  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.replace(~r/[\x00-\x1f\x7f"\\]/, "")
    |> String.trim()
    |> case do
      "" -> "export.csv"
      sanitized -> sanitized
    end
  end

  defp sanitize_filename(_), do: "export.csv"

  defp build_query(%{"query_id" => query_id}) when not is_nil(query_id) do
    Lotus.get_query(query_id)
  end

  defp build_query(%{"query_attrs" => attrs} = params) do
    # Build query struct from attributes (for unsaved queries)
    %Query{
      statement: attrs["statement"],
      data_source: params["repo"],
      search_path: params["search_path"],
      variables: build_variables(attrs["variables"] || [])
    }
  end

  defp build_query(_), do: nil

  defp build_variables(variables) when is_list(variables) do
    Enum.map(variables, fn var ->
      struct(Lotus.Storage.QueryVariable, var)
    end)
  end

  defp build_variables(_), do: []

  defp stream_chunks(conn, query, export_params) do
    repo = export_params["repo"]
    vars = export_params["vars"] || %{}
    search_path = export_params["search_path"]

    opts = [repo: repo, vars: vars]

    opts =
      if search_path && String.trim(search_path) != "" do
        Keyword.put(opts, :search_path, search_path)
      else
        opts
      end

    opts = Actor.merge(opts, resolve_actor(conn))

    query
    |> Export.stream_csv(opts)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  # The export route sits outside the LiveView session, so the dashboard route
  # hands it the resolver in the route's private data and it resolves the actor
  # from the conn itself. A dashboard mounted without a resolver exports
  # unscoped, exactly as it did before.
  defp resolve_actor(conn) do
    case conn.private[:lotus_resolver] do
      nil ->
        {nil, nil}

      resolver ->
        Actor.resolve(resolver, Resolver.call_with_fallback(resolver, :resolve_user, [conn]))
    end
  end

  @doc """
  Generates a signed token for export.

  Returns a signed token valid for #{@max_age} seconds.
  """
  def generate_token(endpoint, params) do
    Phoenix.Token.encrypt(endpoint, @token_salt, params, max_age: @max_age)
  end
end
