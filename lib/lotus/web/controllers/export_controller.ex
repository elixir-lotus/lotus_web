defmodule Lotus.Web.ExportController do
  @moduledoc """
  Controller for streaming CSV exports.
  """

  use Phoenix.Controller, formats: [:csv]

  alias Lotus.Export
  alias Lotus.Query.Filter
  alias Lotus.Query.Sort
  alias Lotus.Web.Actor
  alias Lotus.Web.Authorization
  alias Lotus.Web.Resolver
  alias Lotus.Web.Telemetry
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
  - filters, sorts: optional `Lotus.Query.Filter`s and `Lotus.Query.Sort`s,
    the results' as the person sees them
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

  # The export route sits outside the LiveView session, so the dashboard route
  # hands it the resolver in the route's private data and it resolves the user
  # from the conn itself. A dashboard mounted without a resolver exports
  # unscoped and with full access, exactly as it did before.
  #
  # The token proves the dashboard built the export; it does not prove the
  # user may still export from that source, so ask before loading the query.
  # An export runs the statement in the token, so it needs :query there too.
  defp stream_csv_export(conn, export_params) do
    resolver = conn.private[:lotus_resolver]
    user = Resolver.call_with_fallback(resolver, :resolve_user, [conn])
    access = Resolver.call_with_fallback(resolver, :resolve_access, [user])
    source = export_params["repo"]
    actor = Actor.resolve(resolver, user)

    with :allow <- Authorization.decide(resolver, user, access, :query, source),
         :allow <- Authorization.decide(resolver, user, access, :export, source),
         %Query{} = query <- build_query(export_params, actor) do
      filename =
        export_params
        |> Map.get("filename", "export.csv")
        |> sanitize_filename()

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_chunked(200)
      |> stream_export(query, export_params, actor)
    else
      {:deny, reason} ->
        conn
        |> put_status(:forbidden)
        |> text(reason)

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

  defp build_query(%{"query_id" => query_id}, actor) when not is_nil(query_id) do
    Lotus.get_query(query_id, Actor.opts(actor))
  end

  defp build_query(%{"query_attrs" => attrs} = params, _actor) do
    # Build query struct from attributes (for unsaved queries)
    %Query{
      statement: attrs["statement"],
      data_source: params["repo"],
      search_path: params["search_path"],
      variables: build_variables(attrs["variables"] || [])
    }
  end

  defp build_query(_params, _actor), do: nil

  defp build_variables(variables) when is_list(variables) do
    Enum.map(variables, fn var ->
      struct(Lotus.Storage.QueryVariable, var)
    end)
  end

  defp build_variables(_), do: []

  # The download runs in an `[:lotus_web, :export]` span (`Lotus.Web.Telemetry`).
  defp stream_export(conn, query, export_params, {context, _scope} = actor) do
    metadata = %{
      query: query,
      source: export_params["repo"],
      format: :csv,
      context: context,
      client: Telemetry.client(conn)
    }

    :telemetry.span([:lotus_web, :export], metadata, fn ->
      {conn, bytes, status} = stream_chunks(conn, query, export_params, actor)
      {conn, %{bytes: bytes}, Map.put(metadata, :status, status)}
    end)
  end

  defp stream_chunks(conn, query, export_params, actor) do
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

    opts =
      opts
      |> put_view(:filters, export_params["filters"], Filter)
      |> put_view(:sorts, export_params["sorts"], Sort)
      |> Actor.merge(actor)

    query
    |> Export.stream_csv(opts)
    |> Enum.reduce_while({conn, 0, :ok}, fn data, {conn, bytes, :ok} ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, {conn, bytes + IO.iodata_length(data), :ok}}
        {:error, :closed} -> {:halt, {conn, bytes, :closed}}
      end
    end)
  end

  # The results' filters or sorts, when the token has them: Lotus runs them,
  # and refuses an operator the source does not support.
  defp put_view(opts, key, [_ | _] = items, struct) do
    if Enum.all?(items, &is_struct(&1, struct)), do: Keyword.put(opts, key, items), else: opts
  end

  defp put_view(opts, _key, _items, _struct), do: opts

  @doc """
  Generates a signed token for export.

  Returns a signed token valid for #{@max_age} seconds.
  """
  def generate_token(endpoint, params) do
    Phoenix.Token.encrypt(endpoint, @token_salt, params, max_age: @max_age)
  end
end
