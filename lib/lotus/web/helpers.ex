defmodule Lotus.Web.Helpers do
  @moduledoc false

  use Gettext, backend: Lotus.Web.Gettext

  alias Phoenix.VerifiedRoutes

  # Routing Helpers

  @pdict_key :__lotus_web_prefix__

  @doc false
  def put_router_prefix(socket, prefix) do
    Process.put(@pdict_key, {socket, prefix})
  end

  @doc """
  Construct a path to a dashboard page with optional params.

  Routing is based on a socket and prefix tuple stored in the process dictionary. Proper routing
  can be disabled for testing by setting the value to `:nowhere`.
  """
  def lotus_path(route, params \\ %{})

  def lotus_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> lotus_path(params)
  end

  def lotus_path(route, params) do
    params =
      params
      |> Enum.sort()
      |> encode_params()

    case Process.get(@pdict_key) do
      {socket, prefix} ->
        path = if route == "", do: prefix, else: "#{prefix}/#{route}"
        VerifiedRoutes.unverified_path(socket, socket.router, path, params)

      :nowhere ->
        "/"

      nil ->
        raise RuntimeError, "nothing stored in the #{@pdict_key} key"
    end
  end

  @doc """
  Prepare parsed params for URI encoding.
  """
  def encode_params(params) do
    for {key, val} <- params, val != nil, val != "" do
      case val do
        [path, frag] when is_list(path) ->
          {key, Enum.join(path, ",") <> "++" <> frag}

        [_ | _] ->
          {key, Enum.join(val, ",")}

        _ ->
          {key, val}
      end
    end
  end

  @doc """
  """
  def active_filter?(params, :state, value) do
    params[:state] == value or (is_nil(params[:state]) and value == "executing")
  end

  def active_filter?(params, key, value) do
    params
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.member?(to_string(value))
  end

  @doc """
  The message for a content change that a `:before_content_change` plug refused.

  Shows the plug's reason when it is a string. Any other reason, such as an
  exception, gets a generic message, so internal terms never reach the page.
  """
  def refused_message(reason) when is_binary(reason),
    do: gettext("The change was refused: %{reason}", reason: reason)

  def refused_message(_reason), do: gettext("The change was refused")

  require Logger

  @doc """
  Encodes data to JSON, returning `{:ok, json}` or `{:error, :encoding_failed}`.
  """
  def safe_json_encode(data) do
    {:ok, Lotus.JSON.encode!(data)}
  rescue
    error ->
      Logger.warning("JSON encoding failed: #{Exception.message(error)}")
      {:error, :encoding_failed}
  end

  @doc """
  Encodes data to JSON, returning `"{}"` on failure.
  """
  def safe_json_encode_or_empty(data) do
    Lotus.JSON.encode!(data)
  rescue
    error ->
      Logger.warning("JSON encoding failed: #{Exception.message(error)}")
      "{}"
  end
end
