defmodule Resonance.Live.WorkspaceTest do
  use ExUnit.Case, async: false

  alias Resonance.Live.Workspace
  alias Resonance.LLM.ToolCall
  alias Resonance.Renderable
  alias Resonance.Test.ComponentHelpers
  alias Resonance.WorkspaceCompiler
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section
  alias Resonance.WorkspaceSnapshot

  defmodule Resolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok, [%{label: "Acme", value: 100}, %{label: "Globex", value: 80}]}
    end
  end

  defmodule Provider do
    @behaviour Resonance.LLM.Provider

    @impl true
    def chat(_prompt, _tools, _opts) do
      {:ok,
       [
         %ToolCall{
           id: "plan-1",
           name: "create_workspace_plan",
           arguments: %{
             "goal" => "pipeline_review",
             "title" => "Pipeline review",
             "layout" => "stack",
             "sections" => [
               %{
                 "id" => "stage_mix",
                 "title" => "Pipeline by stage",
                 "role" => "primary",
                 "pattern" => "summary_panel",
                 "source" => %{
                   "type" => "tool_call",
                   "tool_call" => %{
                     "id" => "call_stage_mix",
                     "name" => "show_distribution",
                     "arguments" => %{
                       "dataset" => "deals",
                       "measures" => ["sum(value)"],
                       "dimensions" => ["stage"],
                       "title" => "Pipeline by stage"
                     }
                   }
                 }
               }
             ],
             "refinements" => []
           }
         }
       ]}
    end
  end

  setup do
    old_provider = Application.get_env(:resonance, :provider)
    Application.put_env(:resonance, :provider, Provider)

    on_exit(fn ->
      if is_nil(old_provider),
        do: Application.delete_env(:resonance, :provider),
        else: Application.put_env(:resonance, :provider, old_provider)
    end)
  end

  describe "mount/1" do
    test "initializes the workspace lifecycle" do
      socket = ComponentHelpers.mount_component(Workspace)

      assert socket.assigns.status == :idle
      assert socket.assigns.busy == false
      assert socket.assigns.renderables == []
      assert socket.assigns.snapshot == nil
      assert socket.assigns.workspace_context == nil
    end
  end

  describe "update/2" do
    test "sets app-owned runtime assigns" do
      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver,
          presenter: Resonance.Presenters.Default,
          patterns: [],
          initial_prompt: "Show pipeline"
        })

      assert socket.assigns.id == "workspace"
      assert socket.assigns.resolver == Resolver
      assert socket.assigns.presenter == Resonance.Presenters.Default
      assert socket.assigns.patterns == []
      assert socket.assigns.prompt == "Show pipeline"
    end

    test "accepts a saved snapshot from app-owned persistence" do
      snapshot = snapshot()
      {:ok, snapshot_json} = WorkspaceSnapshot.to_json(snapshot)

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          snapshot_json: snapshot_json
        })

      assert socket.assigns.status == :ready
      assert socket.assigns.snapshot.fingerprint == snapshot.fingerprint
      assert socket.assigns.plan.title == "Pipeline review"
      assert socket.assigns.workspace_context.original_prompt == "Show pipeline"
    end

    test "planner and compiler updates move the lifecycle to ready" do
      {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver
        })

      {:ok, socket} =
        Workspace.update(
          %{id: "workspace", resonance_workspace_planned: %{plan: plan(), attempts: 1}},
          socket
        )

      assert socket.assigns.status == :resolving
      assert socket.assigns.plan == plan()

      {:ok, socket} =
        Workspace.update(
          %{
            id: "workspace",
            resonance_workspace_compiled: %{compiled: compiled, prompt: "Show pipeline"}
          },
          socket
        )

      assert socket.assigns.status == :ready
      assert socket.assigns.busy == false
      assert length(socket.assigns.renderables) == 1
      assert %WorkspaceSnapshot{} = socket.assigns.snapshot
      assert socket.assigns.snapshot_json =~ "Pipeline review"
      assert socket.assigns.workspace_context.original_prompt == "Show pipeline"
    end

    test "rerun events replace renderables and rebuild snapshot context" do
      {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver,
          resonance_workspace_compiled: %{compiled: compiled, prompt: "Show pipeline"}
        })

      [renderable] = socket.assigns.renderables
      updated_result = %{renderable.result | data: [%{label: "Acme", value: 900}]}

      updated = %{
        renderable
        | props: %{renderable.props | data: updated_result.data},
          result: updated_result
      }

      {:ok, socket} =
        Workspace.update(
          %{id: "workspace", resonance_workspace_rerun_event: {:component_ready, updated}},
          socket
        )

      assert [%Renderable{props: %{data: [%{value: 900}]}}] = socket.assigns.renderables

      {:ok, socket} =
        Workspace.update(%{id: "workspace", resonance_workspace_rerun_event: :done}, socket)

      assert socket.assigns.status == :ready

      assert socket.assigns.workspace_context.sections |> hd() |> get_in([:result, :row_count]) ==
               1
    end

    test "failure updates enter failed state" do
      socket = ComponentHelpers.update_component(Workspace, %{id: "workspace"})

      {:ok, socket} =
        Workspace.update(%{id: "workspace", resonance_workspace_failed: :planner_down}, socket)

      assert socket.assigns.status == :failed
      assert socket.assigns.busy == false
      assert socket.assigns.error == :planner_down
    end
  end

  describe "handle_event/3" do
    test "empty generate prompt is a no-op" do
      socket = ComponentHelpers.update_component(Workspace, %{id: "workspace"})

      {:noreply, socket} = Workspace.handle_event("generate", %{"prompt" => ""}, socket)

      assert socket.assigns.status == :idle
      assert socket.assigns.renderables == []
    end

    test "non-empty generate prompt enters planning state" do
      attach_workspace_telemetry()

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver
        })

      {:noreply, socket} =
        Workspace.handle_event("generate", %{"prompt" => "Show pipeline"}, socket)

      assert socket.assigns.status == :planning
      assert socket.assigns.busy == true
      assert socket.assigns.prompt == "Show pipeline"

      assert_receive {:workspace_telemetry, [:resonance, :workspace, :resolve, :stop],
                      %{status: :ok, component_id: "workspace"}},
                     5000
    end

    test "emits workspace planning and resolve telemetry" do
      attach_workspace_telemetry()

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver
        })

      {:noreply, _socket} =
        Workspace.handle_event("generate", %{"prompt" => "Show pipeline"}, socket)

      assert_receive {:workspace_telemetry, [:resonance, :workspace, :planning, :stop],
                      %{status: :ok, component_id: "workspace"}},
                     5000

      assert_receive {:workspace_telemetry, [:resonance, :workspace, :resolve, :stop],
                      %{status: :ok, component_id: "workspace"}},
                     5000
    end

    test "second prompt while busy is ignored and recorded" do
      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          resolver: Resolver
        })
        |> Phoenix.Component.assign(status: :planning, busy: true)

      {:noreply, socket} =
        Workspace.handle_event("generate", %{"prompt" => "Interrupt this"}, socket)

      assert socket.assigns.status == :planning
      assert socket.assigns.ignored_prompt == "Interrupt this"
    end

    test "save uses an app-owned callback when provided" do
      parent = self()
      snapshot = snapshot()

      socket =
        ComponentHelpers.update_component(Workspace, %{
          id: "workspace",
          snapshot: snapshot,
          on_save: fn saved ->
            send(parent, {:saved_workspace, saved.fingerprint})
            :ok
          end
        })

      {:noreply, socket} = Workspace.handle_event("save_workspace", %{}, socket)

      assert_receive {:saved_workspace, fingerprint}
      assert fingerprint == snapshot.fingerprint
      assert socket.assigns.save_status == :saved
    end
  end

  describe "render/1" do
    test "renders prompt, save, and rerun affordances" do
      socket = ComponentHelpers.update_component(Workspace, %{id: "workspace"})

      html = render_to_string(socket)

      assert html =~ "resonance-workspace"
      assert html =~ "What workspace do you need"
      assert html =~ "Generate"
      assert html =~ "Rerun"
      assert html =~ "Save"
    end
  end

  defp snapshot do
    {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})
    WorkspaceSnapshot.from_compiled(compiled, original_prompt: "Show pipeline")
  end

  defp plan do
    %WorkspacePlan{
      goal: :pipeline_review,
      title: "Pipeline review",
      layout: :stack,
      sections: [
        %Section{
          id: "stage_mix",
          title: "Pipeline by stage",
          role: :primary,
          pattern: :summary_panel,
          source:
            {:tool_call,
             %ToolCall{
               id: "call_stage_mix",
               name: "show_distribution",
               arguments: %{
                 "dataset" => "deals",
                 "measures" => ["sum(value)"],
                 "dimensions" => ["stage"],
                 "title" => "Pipeline by stage"
               }
             }}
        }
      ]
    }
  end

  defp render_to_string(socket) do
    assigns = Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})

    Workspace.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp attach_workspace_telemetry do
    handler_id = "workspace-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:resonance, :workspace, :planning, :stop],
        [:resonance, :workspace, :resolve, :stop]
      ],
      fn event, _measurements, metadata, pid ->
        send(pid, {:workspace_telemetry, event, metadata})
      end,
      parent
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
