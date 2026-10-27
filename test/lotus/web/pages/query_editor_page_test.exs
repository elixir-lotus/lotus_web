defmodule Lotus.Web.Pages.QueryEditorPageTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  describe "query editor page" do
    test "loads the new query page" do
      {:ok, _live, html} = live(build_conn(), "/lotus/queries/new")

      # Verify the page loads with expected elements
      assert html =~ "New Query"
      assert html =~ "Save"

      # Verify the editor component is present
      assert html =~ "query-editor-page"
      assert html =~ "editor"
    end

    test "loads an existing query and auto-runs it" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Test Users Query",
          statement: "SELECT name, email FROM test_users WHERE active = true ORDER BY name",
          description: "A test query for users"
        })

      {:ok, live, html} = live(build_conn(), "/lotus/queries/#{query.id}")

      assert html =~ "Test Users Query"
      assert html =~ "SELECT name, email FROM test_users"

      # Verify the query auto-ran and shows results
      # Should see the active users (Alice and Charlie)
      assert render_async(live) =~ "Alice"
      assert render(live) =~ "alice@test.com"
      assert render(live) =~ "Charlie"
      assert render(live) =~ "charlie@test.com"

      # Should NOT see inactive user (Bob)
      refute render(live) =~ "bob@test.com"
    end

    test "new query page loads" do
      {:ok, _live, html} = live(build_conn(), "/lotus/queries/new")

      assert html =~ "New Query"
      assert html =~ "Save"
      assert html =~ "disabled"

      assert html =~ "To run your query, click on the Run button"
    end
  end

  describe "variable default values" do
    test "auto-runs query with variable default value" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Default Value Query",
          statement: "SELECT name, email FROM test_users WHERE name = {{name}}",
          variables: [%{name: "name", type: "text", widget: "input", default: "Alice"}]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      # The query should auto-run with default value "Alice"
      html = render_async(live)
      assert html =~ "Alice"
      assert html =~ "alice@test.com"
      refute html =~ "bob@test.com"
    end

    test "a query opened with values for its variables runs with them (a dashboard card's)" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Prefilled Query",
          statement: "SELECT name, email FROM test_users WHERE name = {{name}}",
          variables: [%{name: "name", type: "text", widget: "input", default: "Alice"}]
        })

      {:ok, live, _html} =
        live(build_conn(), "/lotus/queries/#{query.id}?vars[name]=Bob&vars[other]=x")

      assert has_element?(live, ~s(input[name="variables[name]"][value="Bob"]))
      html = render_async(live)
      assert html =~ "bob@test.com"
      refute html =~ "alice@test.com"
    end

    test "a date variable is a date picker with its default" do
      query =
        query_fixture(%{
          name: "Date Variable Query",
          statement: "SELECT CAST({{since}} AS text) AS since",
          variables: [%{name: "since", type: "date", widget: "input", default: "2026-01-15"}]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      assert has_element?(live, ~s(#variable_since[phx-hook=Koyomi][data-value='"2026-01-15"']))

      assert has_element?(
               live,
               ~s(#variable_since input[name="variables[since]"][value="2026-01-15"])
             )

      assert render_async(live) =~ "2026-01-15"
    end

    test "empty toolbar input does not override variable default on run" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Default Value Query",
          statement: "SELECT name, email FROM test_users WHERE name = {{name}}",
          variables: [%{name: "name", type: "text", widget: "input", default: "Alice"}]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      # Wait for auto-run to complete
      assert render_async(live) =~ "alice@test.com"

      # Manually run with empty toolbar input — should still use default
      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_submit(%{
        "query" => %{"statement" => "SELECT name, email FROM test_users WHERE name = {{name}}"},
        "variables" => %{"name" => ""}
      })

      # Wait for async query execution and verify default was used
      html = render_async(live)
      assert html =~ "alice@test.com"
      refute html =~ "bob@test.com"
    end
  end

  describe "AI variable wiring" do
    defp set_ai_conversation(live, conversation) do
      Phoenix.LiveView.send_update(
        live.pid,
        Lotus.Web.QueryEditorPage,
        id: "page",
        ai_conversation: conversation,
        left_drawer: :ai_assistant
      )

      render(live)
    end

    defp build_ai_conversation(messages) do
      %{
        messages: messages,
        source_context: %{tables_analyzed: []},
        generation_count: length(Enum.filter(messages, &(&1.role == :assistant))),
        started_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
    end

    test "use_ai_query applies AI variables directly without JS hook" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "select",
          "label" => "Status",
          "static_options" => [
            %{"value" => "active", "label" => "Active"},
            %{"value" => "inactive", "label" => "Inactive"}
          ]
        }
      ]

      conversation =
        build_ai_conversation([
          %{
            role: :user,
            content: "Show orders with a status dropdown",
            statement: nil,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :assistant,
            content: "Here's your SQL query:",
            statement: "SELECT * FROM orders WHERE status = {{status}}",
            variables: ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, conversation)

      live
      |> element(~s(button[phx-click="use_ai_query"]))
      |> render_click()

      # The variable settings panel should show with the variable configured
      # No need to simulate variables_detected — variables are applied directly
      html = render(live)
      assert html =~ "Status"
      # Select widget should be rendered (dropdown)
      assert html =~ "select"
    end

    test "the steps the model takes show while it answers" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      conversation =
        build_ai_conversation([
          %{
            role: :user,
            content: "Revenue by month",
            statement: nil,
            timestamp: DateTime.utc_now()
          }
        ])

      Phoenix.LiveView.send_update(live.pid, Lotus.Web.QueryEditorPage,
        id: "page",
        ai_conversation: conversation,
        ai_generating: true,
        ai_action: :generate,
        left_drawer: :ai_assistant
      )

      for event <- [
            %{phase: :start, id: 1, tool: "describe_table", args: %{"table_name" => "orders"}},
            %{
              phase: :stop,
              id: 1,
              result: ~s({"columns":[{"name":"id"},{"name":"total"}]}),
              duration: 0
            }
          ] do
        Phoenix.LiveView.send_update(live.pid, Lotus.Web.QueryEditorPage,
          id: "page",
          action: :ai_tool_call,
          event: event
        )
      end

      html = render(live)
      assert html =~ "Writing the query"
      assert html =~ "Reading orders"
      assert html =~ "2 columns"
    end

    test "what the user points at rides with the message, as chips" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
      set_ai_conversation(live, build_ai_conversation([]))

      context =
        Lotus.JSON.encode!([
          %{
            "kind" => "row",
            "label" => "row 1 · status = pending",
            "detail" => "row 1 of the results"
          }
        ])

      html =
        live
        |> form("#ai-message-form", %{"message" => "Why is this pending?"})
        # The hook sets the hidden field, which the form renders empty.
        |> render_submit(%{"context" => context})

      assert html =~ "row 1 · status = pending"
      assert html =~ "Why is this pending?"
      refute html =~ "I am pointing at"
    end

    test "a previewed answer's chart goes into the editor as that chart" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      conversation =
        build_ai_conversation([
          %{
            role: :user,
            content: "Users by status",
            statement: nil,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :assistant,
            content: "Here's your query:",
            statement: "SELECT status, count(*) AS users FROM users GROUP BY 1",
            variables: [],
            timestamp: DateTime.utc_now(),
            preview: %{
              status: :ok,
              columns: ["status", "users"],
              rows: [["active", 3], ["inactive", 1]],
              error: nil,
              chart: %{
                type: "bar",
                x: "status",
                y: "users",
                points: [{"active", 3}, {"inactive", 1}]
              }
            }
          }
        ])

      html = set_ai_conversation(live, conversation)
      assert html =~ "Use as bar chart"
      assert html =~ "users by status"

      live
      |> element(~s(button[phx-click="use_ai_chart"]))
      |> render_click()

      html = render_async(live)
      assert html =~ "SELECT status, count(*) AS users FROM users GROUP BY 1"
    end

    test "variables_detected without pending AI variables uses defaults" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      # Simulate JS detecting a variable without any AI context
      live
      |> element(~s([phx-hook="EditorForm"]))
      |> render_hook("variables_detected", %{"variables" => ["user_name"]})

      html = render(live)
      # Variable should appear with default label formatting
      assert html =~ "User Name"
    end

    test "AI variable configs override existing variables" do
      query =
        query_fixture(%{
          name: "Existing Vars Query",
          statement: "SELECT * FROM orders WHERE status = {{status}}",
          variables: [
            %{
              name: "status",
              type: "text",
              widget: "select",
              label: "Order Status",
              static_options: [
                %{value: "pending", label: "Pending"},
                %{value: "shipped", label: "Shipped"}
              ]
            }
          ]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "input",
          "label" => "AI Status"
        }
      ]

      conversation =
        build_ai_conversation([
          %{
            role: :assistant,
            content: "Here's your query:",
            statement: "SELECT * FROM orders WHERE status = {{status}}",
            variables: ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, conversation)

      live
      |> element(~s(button[phx-click="use_ai_query"]))
      |> render_click()

      html = render(live)
      # AI label "AI Status" should override existing "Order Status"
      assert html =~ "AI Status"
      refute html =~ "Order Status"
    end

    test "existing variables preserved when no AI configs provided" do
      query =
        query_fixture(%{
          name: "Existing Vars Query",
          statement: "SELECT * FROM orders WHERE status = {{status}}",
          variables: [
            %{
              name: "status",
              type: "text",
              widget: "select",
              label: "Order Status",
              static_options: [
                %{value: "pending", label: "Pending"},
                %{value: "shipped", label: "Shipped"}
              ]
            }
          ]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      # Trigger variable detection without any AI context
      live
      |> element(~s([phx-hook="EditorForm"]))
      |> render_hook("variables_detected", %{"variables" => ["status"]})

      html = render(live)
      # Existing label "Order Status" should be preserved
      assert html =~ "Order Status"
    end

    test "pending variables are cleared after detection consumes them" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "select",
          "label" => "Status",
          "static_options" => [
            %{"value" => "active", "label" => "Active"}
          ]
        }
      ]

      conversation =
        build_ai_conversation([
          %{
            role: :assistant,
            content: "Here's your query:",
            statement:
              "SELECT * FROM orders WHERE status = {{status}} AND category = {{category}}",
            variables: ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, conversation)

      live
      |> element(~s(button[phx-click="use_ai_query"]))
      |> render_click()

      # First detection — consumes AI variables
      live
      |> element(~s([phx-hook="EditorForm"]))
      |> render_hook("variables_detected", %{"variables" => ["status", "category"]})

      # Second detection (e.g., user edits query) — AI vars already consumed
      live
      |> element(~s([phx-hook="EditorForm"]))
      |> render_hook("variables_detected", %{"variables" => ["status", "category", "new_var"]})

      html = render(live)
      # new_var should use defaults since AI vars were consumed
      assert html =~ "New Var"
    end

    test "clear_ai_conversation preserves already-applied variable settings" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "select",
          "label" => "Custom Label",
          "static_options" => [
            %{"value" => "active", "label" => "Active"}
          ]
        }
      ]

      conversation =
        build_ai_conversation([
          %{
            role: :assistant,
            content: "Here's your query:",
            statement: "SELECT * FROM orders WHERE status = {{status}}",
            variables: ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, conversation)

      # Use the query — variables are applied directly
      live
      |> element(~s(button[phx-click="use_ai_query"]))
      |> render_click()

      # Verify AI variables were applied
      assert render(live) =~ "Custom Label"

      # Clear the conversation
      live
      |> element(~s(button[phx-click="clear_ai_conversation"]))
      |> render_click()

      # Detect variables — applied vars should be preserved as existing
      live
      |> element(~s([phx-hook="EditorForm"]))
      |> render_hook("variables_detected", %{"variables" => ["status"]})

      html = render(live)
      # Already-applied "Custom Label" should be preserved since it's now an existing variable
      assert html =~ "Custom Label"
    end

    test "variable-only change applies new variable settings with contextual flash" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      statement = "SELECT * FROM orders WHERE status = {{status}}"

      # First: set up initial query with dropdown variable
      first_ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "select",
          "label" => "Status",
          "static_options" => [
            %{"value" => "active", "label" => "Active"},
            %{"value" => "inactive", "label" => "Inactive"}
          ]
        }
      ]

      conversation =
        build_ai_conversation([
          %{
            role: :user,
            content: "Show orders with a status dropdown",
            statement: nil,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :assistant,
            content: "Here's your query:",
            statement: statement,
            variables: first_ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, conversation)

      live
      |> element(~s(button[phx-click="use_ai_query"]))
      |> render_click()

      # Verify initial dropdown setup
      html = render(live)
      assert html =~ "select"

      # Now: AI returns same SQL but with input widget instead of select
      updated_ai_variables = [
        %{
          "name" => "status",
          "type" => "text",
          "widget" => "input",
          "label" => "Status Filter"
        }
      ]

      updated_conversation =
        build_ai_conversation([
          %{
            role: :user,
            content: "Show orders with a status dropdown",
            statement: nil,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :assistant,
            content: "Here's your query:",
            statement: statement,
            variables: first_ai_variables,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :user,
            content: "Change status to a freeform input",
            statement: nil,
            timestamp: DateTime.utc_now()
          },
          %{
            role: :assistant,
            content: "Updated the variable:",
            statement: statement,
            variables: updated_ai_variables,
            timestamp: DateTime.utc_now()
          }
        ])

      set_ai_conversation(live, updated_conversation)

      # Click "Use this query" on the second AI message (index 3)
      # The button for the latest assistant message
      live
      |> element(~s(button[phx-click="use_ai_query"][phx-value-message-index="3"]))
      |> render_click()

      html = render(live)
      # Variable label should be updated to "Status Filter"
      assert html =~ "Status Filter"
      # Toast should indicate variable-only change
      assert_push_event(live, "toast", %{message: "Variable settings updated"})
    end
  end

  describe "query timeout selector (enabled via features: [:timeout_options])" do
    test "renders the timeout selector with default value of 5s" do
      {:ok, _live, html} = live(build_conn(), "/lotus/queries/new")

      assert html =~ "timeout-selector-tippy"
      assert html =~ ~s(name="query_timeout")
      assert html =~ ~s(value="5000" selected)
      assert html =~ ~s(value="15000")
      assert html =~ ~s(value="30000")
      assert html =~ ~s(value="60000")
      assert html =~ ~s(value="120000")
      assert html =~ ~s(value="300000")
      assert html =~ ~s(value="0")
    end

    test "changing the timeout value updates the selector" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      html =
        live
        |> element(~s(form[phx-submit="run_query"]))
        |> render_change(%{"query_timeout" => "30000", "query" => %{"statement" => ""}})

      assert html =~ ~s(value="30000" selected)
      refute html =~ ~s(value="5000" selected)
    end

    test "submits a query with custom timeout" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      # Set timeout to 60s and provide the statement
      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{
        "query_timeout" => "60000",
        "query" => %{"statement" => "SELECT 1 as result"}
      })

      # Run the query - verify submission doesn't error
      html =
        live
        |> element(~s(form[phx-submit="run_query"]))
        |> render_submit(%{
          "query" => %{
            "statement" => "SELECT 1 as result"
          }
        })

      # Verify the timeout selector still shows 60s after submission
      assert html =~ ~s(value="60000" selected)
      # Query should be running (no error about empty statement)
      refute html =~ "Please enter a SQL statement"
    end

    test "timeout selector persists value across form changes" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      # Set timeout to 2 minutes
      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{"query_timeout" => "120000", "query" => %{"statement" => ""}})

      # Make another form change (e.g. typing in the editor)
      html =
        live
        |> element(~s(form[phx-submit="run_query"]))
        |> render_change(%{"query" => %{"statement" => "SELECT 1"}})

      # Timeout should still be 2m
      assert html =~ ~s(value="120000" selected)
    end
  end

  describe "dropdown options" do
    test "a change in the variable settings keeps the options from a query" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      live
      |> with_target("#query-editor-page")
      |> render_hook("editor_content_changed", %{"statement" => "SELECT {{status}} AS status"})

      live
      |> with_target("#query-editor-page")
      |> render_hook("variables_detected", %{"variables" => ["status"]})

      live |> element("#variable-settings-btn") |> render_click()

      # The variable settings form sends no data source
      live
      |> element("#variable-settings-form")
      |> render_change(%{"query" => %{"variables" => %{"0" => %{"widget" => "select"}}}})

      html =
        live
        |> element(~s([phx-click="open_dropdown_options_modal"]))
        |> render_click()

      assert html =~ "From query"
    end
  end

  describe "saving a query" do
    test "records the query language of the selected data source" do
      {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

      live
      |> element(~s(form[phx-submit="run_query"]))
      |> render_change(%{"query" => %{"statement" => "SELECT 1 as result"}})

      live
      |> element(~s(form[phx-submit="save_query"]))
      |> render_submit(%{"query" => %{"name" => "Language Test", "description" => ""}})

      assert [%{name: "Language Test"} = saved] = Lotus.list_queries()
      assert saved.query_language == Lotus.Source.query_language(saved.data_source)
      assert saved.query_language == "sql:postgres"
    end
  end

  describe "dropdown variable options" do
    test "populates a dropdown from its options query" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Dropdown Options Query",
          statement: "SELECT email FROM test_users WHERE name = {{name}}",
          data_source: "public",
          variables: [
            %{
              name: "name",
              type: "text",
              widget: "select",
              options_query: "SELECT DISTINCT name FROM test_users ORDER BY name"
            }
          ]
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")

      html = render_async(live)

      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Charlie"
    end
  end
end
