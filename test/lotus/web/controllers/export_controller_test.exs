defmodule Lotus.Web.Controllers.ExportControllerTest do
  use Lotus.Web.Case, async: true

  use Phoenix.VerifiedRoutes,
    endpoint: Lotus.Web.Endpoint,
    router: Lotus.Web.Test.Router

  alias Lotus.Web.ExportController

  describe "GET /export/csv" do
    setup do
      conn = build_conn()

      %{conn: conn}
    end

    test "returns 400 when token is missing", %{conn: conn} do
      conn = get(conn, ~p"/lotus/export/csv")

      assert conn.status == 400
      assert conn.resp_body == "Missing export token."
    end

    test "returns 401 with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/lotus/export/csv?token=invalid_token_here")

      assert conn.status == 401
      assert conn.resp_body == "Invalid export token"
    end

    test "returns 401 with tampered token", %{conn: conn} do
      # Generate a valid token then tamper with it
      params = %{
        "query_id" => "123",
        "repo" => "public",
        "vars" => %{},
        "filename" => "test.csv"
      }

      valid_token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      tampered_token = valid_token <> "tampered"

      conn = get(conn, ~p"/lotus/export/csv?token=#{tampered_token}")

      assert conn.status == 401
      assert conn.resp_body == "Invalid export token"
    end

    test "returns 401 with expired token", %{conn: conn} do
      params = %{
        "query_id" => "123",
        "repo" => "public",
        "vars" => %{},
        "filename" => "test.csv"
      }

      expired_token =
        Phoenix.Token.encrypt(
          Lotus.Web.Endpoint,
          "lotus_export",
          params,
          signed_at: System.system_time(:second) - 400
        )

      conn = get(conn, ~p"/lotus/export/csv?token=#{expired_token}")

      assert conn.status == 401
      assert conn.resp_body == "Export link has expired. Please try again"
    end

    test "streams CSV with valid token for saved query", %{conn: conn} do
      create_test_users()

      query =
        query_fixture(%{
          name: "Test Users Query",
          statement: "SELECT * FROM test_users"
        })

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => "users_export.csv"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="users_export.csv")
             ]

      assert conn.resp_body =~ "name,email"
      assert conn.resp_body =~ "Alice"
      assert conn.resp_body =~ "alice@test.com"
      assert conn.resp_body =~ "Bob"
      assert conn.resp_body =~ "bob@test.com"
    end

    test "streams CSV with valid token for unsaved query", %{conn: conn} do
      create_test_users()

      params = %{
        "query_attrs" => %{
          "statement" => "SELECT * FROM test_users WHERE name = {{name}}",
          "variables" => [
            %{
              "default" => nil,
              "label" => "Name",
              "name" => "name",
              "options_query" => nil,
              "static_options" => [],
              "type" => :text,
              "widget" => :input
            }
          ]
        },
        "repo" => "public",
        "vars" => %{"name" => "Alice"},
        "filename" => "unsaved_users_export.csv"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="unsaved_users_export.csv")
             ]

      assert conn.resp_body =~ "name,email"
      assert conn.resp_body =~ "Alice"
      assert conn.resp_body =~ "alice@test.com"
      refute conn.resp_body =~ "Bob"
    end

    test "exports the rows as filtered and sorted in the results, every page", %{conn: conn} do
      create_test_users()
      query = query_fixture(%{name: "Users", statement: "SELECT name, age FROM test_users"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filters" => [Lotus.Query.Filter.new("age", :gte, 30)],
        "sorts" => [Lotus.Query.Sort.new("name", :desc)]
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      assert String.split(conn.resp_body, ~r/\r?\n/, trim: true) == [
               "name,age",
               "Charlie,35",
               "Alice,30"
             ]
    end

    test "returns error message when query not found", %{conn: conn} do
      params = %{
        "query_id" => 9999,
        "repo" => "public",
        "vars" => %{},
        "filename" => "export.csv"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)

      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 404
      assert conn.resp_body == "Query not found."
    end

    test "uses default filename when not provided", %{conn: conn} do
      query = query_fixture(%{statement: "SELECT 1 as result"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{}
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="export.csv")
             ]

      assert conn.resp_body =~ "result"
    end

    test "strips CRLF from filename to prevent header injection", %{conn: conn} do
      query = query_fixture(%{statement: "SELECT 1 as result"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => "evil.csv\"\r\nX-Injected: pwned"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      [content_disposition] = get_resp_header(conn, "content-disposition")
      refute content_disposition =~ ~r/[\r\n]/
      assert content_disposition == ~s(attachment; filename="evil.csvX-Injected: pwned")
    end

    test "strips null bytes, backslashes, and double-quotes from filename", %{conn: conn} do
      query = query_fixture(%{statement: "SELECT 1 as result"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => "my\\\"file\x00.csv"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="myfile.csv")
             ]
    end

    test "falls back to default when sanitized filename is empty", %{conn: conn} do
      query = query_fixture(%{statement: "SELECT 1 as result"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => ~s("""")
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="export.csv")
             ]
    end

    test "falls back to default when filename is only whitespace", %{conn: conn} do
      query = query_fixture(%{statement: "SELECT 1 as result"})

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{},
        "filename" => "   \t  "
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)
      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="export.csv")
             ]
    end

    test "streams CSV with variables", %{conn: conn} do
      create_test_users()

      query =
        query_fixture(%{
          name: "Filtered Users Query",
          statement: "SELECT * FROM test_users WHERE name = {{name}}",
          variables: [
            %{name: "name", type: "text", default: "Alice"}
          ]
        })

      params = %{
        "query_id" => query.id,
        "repo" => "public",
        "vars" => %{"name" => "Alice"},
        "filename" => "filtered_users.csv"
      }

      token = ExportController.generate_token(Lotus.Web.Endpoint, params)

      conn = get(conn, ~p"/lotus/export/csv?token=#{token}")

      assert conn.status == 200
      assert conn.resp_body =~ "Alice"
    end
  end
end
