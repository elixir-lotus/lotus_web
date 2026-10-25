defmodule Lotus.Web.ProDownloadControllerTest do
  @moduledoc """
  A file a Lotus Pro page makes (`Lotus.Web.Pro.download/3`): the page signs
  what to make with `download_path/3`, the route asks Pro as the user.
  `ProWeb` stands in for `Lotus.Pro.Web`.
  """
  use Lotus.Web.Case, async: false

  defmodule ProWeb do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def download("report", %{"kind" => "denied"}, _info), do: {:error, :forbidden}

    def download("report", params, info) do
      send(:persistent_term.get({__MODULE__, :test}), {:download, params, info})
      {:ok, %{filename: "re\"port.csv", content_type: "text/csv", body: ["a,b\r\n", "1,2\r\n"]}}
    end

    def download(_name, _params, _info), do: nil
  end

  setup do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    :persistent_term.put({ProWeb, :test}, self())

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({ProWeb, :test})
    end)
  end

  defp path(name, params) do
    # As a page of the dashboard at /lotus stores it.
    socket = %Phoenix.LiveView.Socket{endpoint: Lotus.Web.Endpoint, router: Lotus.Web.Test.Router}
    Process.put(:__lotus_web_prefix__, {socket, "/lotus"})

    Lotus.Web.Pro.download_path(Lotus.Web.Endpoint, name, params)
  end

  test "sends the file Pro makes, asked as the user" do
    conn = get(build_conn(), path("report", %{"kind" => "all"}))

    assert conn.status == 200
    assert conn.resp_body == "a,b\r\n1,2\r\n"
    assert ["text/csv" <> _] = get_resp_header(conn, "content-type")
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="report.csv")]
    assert_received {:download, %{"kind" => "all"}, %{params: %{"kind" => "all"}}}
  end

  test "Pro's refusal is a 403, a file it does not make a 404" do
    assert get(build_conn(), path("report", %{"kind" => "denied"})).status == 403
    assert get(build_conn(), path("other", %{})).status == 404
  end

  test "a token that is not one is refused" do
    assert get(build_conn(), "/lotus/pro/download?token=nope").status == 401
    assert get(build_conn(), "/lotus/pro/download").status == 400
  end
end
