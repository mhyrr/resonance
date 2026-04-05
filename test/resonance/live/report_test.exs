defmodule Resonance.Live.ReportTest do
  use ExUnit.Case, async: true

  alias Resonance.Live.Report
  alias Resonance.Renderable
  alias Resonance.Test.ComponentHelpers

  # ---------------------------------------------------------------------------
  # mount/1
  # ---------------------------------------------------------------------------

  describe "mount/1" do
    test "initializes with default assigns" do
      socket = ComponentHelpers.mount_component(Report)
      assigns = socket.assigns

      assert assigns.components == []
      assert assigns.loading == false
      assert assigns.prompt == ""
      assert assigns.error == nil
      assert assigns.tool_calls == nil
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — basic assigns
  # ---------------------------------------------------------------------------

  describe "update/2 with basic assigns" do
    test "sets id and resolver" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      assert socket.assigns.id == "test-report"
      assert socket.assigns.resolver == Resonance.Test.MockResolver
    end

    test "preserves existing state on subsequent updates" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      # Simulate a second update that does not provide components/loading/prompt
      {:ok, socket} = Report.update(%{id: "test-report"}, socket)

      assert socket.assigns.components == []
      assert socket.assigns.loading == false
      assert socket.assigns.prompt == ""
    end

    test "accepts optional presenter assign" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver,
          presenter: Resonance.Presenters.Default
        })

      assert socket.assigns.presenter == Resonance.Presenters.Default
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — streaming: resonance_component
  # ---------------------------------------------------------------------------

  describe "update/2 with resonance_component" do
    setup do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      %{socket: socket}
    end

    test "appends new renderable to components", %{socket: socket} do
      renderable =
        Renderable.ready("rank_entities", Resonance.Components.DataTable, %{
          title: "Test",
          data: [%{label: "A", value: 1}]
        })

      {:ok, socket} = Report.update(%{id: "test-report", resonance_component: renderable}, socket)

      assert length(socket.assigns.components) == 1
      assert hd(socket.assigns.components).id == renderable.id
    end

    test "replaces existing renderable with same id", %{socket: socket} do
      renderable = %Renderable{
        id: "stable-1",
        type: "rank_entities",
        component: Resonance.Components.DataTable,
        props: %{title: "V1", data: []},
        status: :ready
      }

      {:ok, socket} = Report.update(%{id: "test-report", resonance_component: renderable}, socket)
      assert length(socket.assigns.components) == 1

      updated = %{renderable | props: %{title: "V2", data: [%{x: 1}]}}
      {:ok, socket} = Report.update(%{id: "test-report", resonance_component: updated}, socket)

      assert length(socket.assigns.components) == 1
      assert hd(socket.assigns.components).props.title == "V2"
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — streaming: resonance_tool_calls
  # ---------------------------------------------------------------------------

  describe "update/2 with resonance_tool_calls" do
    test "stores tool calls for later refresh" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      tool_calls = [
        %Resonance.LLM.ToolCall{
          id: "tc-1",
          name: "rank_entities",
          arguments: %{"dataset" => "test"}
        }
      ]

      {:ok, socket} =
        Report.update(%{id: "test-report", resonance_tool_calls: tool_calls}, socket)

      assert socket.assigns.tool_calls == tool_calls
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — streaming: resonance_done
  # ---------------------------------------------------------------------------

  describe "update/2 with resonance_done" do
    test "sets loading to false" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      # Simulate loading state
      socket = Phoenix.Component.assign(socket, :loading, true)
      assert socket.assigns.loading == true

      {:ok, socket} = Report.update(%{id: "test-report", resonance_done: true}, socket)

      assert socket.assigns.loading == false
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — error path
  # ---------------------------------------------------------------------------

  describe "update/2 with resonance_result error" do
    test "sets error and stops loading" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :loading, true)

      {:ok, socket} =
        Report.update(
          %{id: "test-report", resonance_result: {:error, {:api_error, 429, %{}}}},
          socket
        )

      assert socket.assigns.error == {:api_error, 429, %{}}
      assert socket.assigns.loading == false
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — set_prompt from parent
  # ---------------------------------------------------------------------------

  describe "update/2 with set_prompt" do
    test "sets the prompt assign" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      {:ok, socket} =
        Report.update(%{id: "test-report", set_prompt: "show top deals"}, socket)

      assert socket.assigns.prompt == "show top deals"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event — generate
  # ---------------------------------------------------------------------------

  describe "handle_event generate" do
    test "empty prompt is a no-op" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      {:noreply, socket} = Report.handle_event("generate", %{"prompt" => ""}, socket)

      assert socket.assigns.loading == false
      assert socket.assigns.components == []
    end

    test "non-empty prompt sets loading and clears previous state" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      # Put some prior state in
      socket =
        socket
        |> Phoenix.Component.assign(:error, {:api_error, 500, %{}})
        |> Phoenix.Component.assign(:components, [
          Renderable.ready("test", Resonance.Components.DataTable, %{})
        ])

      # Configure the mock provider so the LLM call succeeds
      Application.put_env(:resonance, :provider, Resonance.Test.MockProvider)

      {:noreply, socket} =
        Report.handle_event("generate", %{"prompt" => "show top deals"}, socket)

      assert socket.assigns.loading == true
      assert socket.assigns.prompt == "show top deals"
      assert socket.assigns.error == nil
      assert socket.assigns.components == []
    after
      Application.put_env(:resonance, :provider, :test)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event — clear
  # ---------------------------------------------------------------------------

  describe "handle_event clear" do
    test "resets all state" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      # Simulate populated state
      socket =
        socket
        |> Phoenix.Component.assign(:components, [
          Renderable.ready("test", Resonance.Components.DataTable, %{})
        ])
        |> Phoenix.Component.assign(:loading, true)
        |> Phoenix.Component.assign(:prompt, "some query")
        |> Phoenix.Component.assign(:error, {:api_error, 500, %{}})

      {:noreply, socket} = Report.handle_event("clear", %{}, socket)

      assert socket.assigns.components == []
      assert socket.assigns.loading == false
      assert socket.assigns.prompt == ""
      assert socket.assigns.error == nil
    end
  end

  # ---------------------------------------------------------------------------
  # update/2 — resolver can be swapped
  # ---------------------------------------------------------------------------

  describe "update/2 resolver swap" do
    test "updates resolver when provided in assigns" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      assert socket.assigns.resolver == Resonance.Test.MockResolver

      {:ok, socket} =
        Report.update(%{id: "test-report", resolver: SomeOtherResolver}, socket)

      assert socket.assigns.resolver == SomeOtherResolver
    end
  end

  # ---------------------------------------------------------------------------
  # format_error (tested indirectly through render, but we can test the private
  # function via the render output by setting error assigns)
  # ---------------------------------------------------------------------------

  describe "render/1 with errors" do
    test "renders error banner when error is set" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :error, {:api_error, 429, %{}})

      # render/1 returns a HEEx template — we can convert to string to assert content
      html = render_to_string(socket)

      assert html =~ "Something went wrong"
      assert html =~ "API error (429)"
    end

    test "renders request_failed error" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :error, {:request_failed, :timeout})
      html = render_to_string(socket)

      assert html =~ "Could not reach the LLM provider"
    end

    test "renders unknown_primitive error" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :error, {:unknown_primitive, "bad_tool"})
      html = render_to_string(socket)

      assert html =~ "Unknown analysis type: bad_tool"
    end

    test "renders query_failed error" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :error, {:query_failed, "column not found"})
      html = render_to_string(socket)

      assert html =~ "Data query failed: column not found"
    end
  end

  describe "render/1 basic structure" do
    test "renders prompt input and generate button" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      html = render_to_string(socket)

      assert html =~ "resonance-report"
      assert html =~ "resonance-prompt-input"
      assert html =~ "Generate"
      assert html =~ ~s(placeholder="What would you like to see?")
    end

    test "renders loading indicator when loading" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      socket = Phoenix.Component.assign(socket, :loading, true)
      html = render_to_string(socket)

      assert html =~ "Generating..."
      assert html =~ "Composing your report..."
      assert html =~ "resonance-loading"
    end

    test "does not render loading indicator when not loading" do
      socket =
        ComponentHelpers.update_component(Report, %{
          id: "test-report",
          resolver: Resonance.Test.MockResolver
        })

      html = render_to_string(socket)

      refute html =~ "Composing your report..."
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp render_to_string(socket) do
    assigns = Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})

    Report.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
