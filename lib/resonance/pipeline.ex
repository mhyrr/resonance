defmodule Resonance.Pipeline do
  @moduledoc """
  The canonical Resonance execution pipeline.

  One function — `run/3` — owns the entire path from a user prompt through
  LLM tool selection, parallel primitive resolution, and event delivery.
  Both the public streaming API (`Resonance.generate_stream/3`) and the
  in-library LiveView surface (`Resonance.Live.Report`) consume this
  pipeline via a sink callback, so stable IDs, error wrapping, task
  supervision, and telemetry live in exactly one place.

  ## The sink contract

  A sink is a unary function that receives pipeline events. Each event
  represents a moment in the pipeline the caller may want to react to:

      {:tool_calls, [ToolCall.t()]}    # after the LLM returns tool calls
      {:component_ready, Renderable.t()}  # per resolved primitive
      :done                            # all primitives resolved
      {:error, term()}                 # LLM failure or pipeline crash

  The sink decides how to deliver. The public API sinks to `send(pid, ...)`.
  Live.Report sinks to `send_update(LiveComponent, id, ...)`. Custom
  consumers can sink anywhere — websockets, ETS, a GenServer, whatever.

  ## Stable IDs

  When resolving a list of tool calls, each resulting `Renderable` is
  stamped with a deterministic `id` of the form `"<primitive_name>-<index>"`.
  Same tool calls always produce the same ids, which lets LiveView
  re-render components in place across refreshes instead of remounting.

  ## Refresh without the LLM

  `resolve/3` is the LLM-free sibling of `run/3`: given a list of tool
  calls you've already stored (typically from a prior `run/3` invocation),
  it re-resolves them against the current context and emits the same
  events, minus the LLM call and the `{:tool_calls, ...}` event. This is
  how `Live.Report`'s refresh path stays consistent with the initial
  generation path.
  """

  require Logger
  alias Resonance.{Composer, LLM, Registry, Renderable}

  @type event ::
          {:tool_calls, [Resonance.LLM.ToolCall.t()]}
          | {:component_ready, Renderable.t()}
          | :done
          | {:error, term()}

  @type sink :: (event -> any())

  @doc """
  Run a prompt through the full pipeline: LLM tool selection,
  parallel primitive resolution, event delivery.

  Spawns a supervised task and returns `:ok` immediately. Events are
  delivered to `sink` asynchronously from the task.
  """
  @spec run(String.t(), map(), sink()) :: :ok
  def run(prompt, context, sink) when is_function(sink, 1) do
    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      try do
        case LLM.chat(prompt, Registry.all_schemas(), context) do
          {:ok, tool_calls} ->
            Logger.info(
              "[Resonance] LLM returned #{length(tool_calls)} tool call(s): " <>
                Enum.map_join(tool_calls, ", ", & &1.name)
            )

            sink.({:tool_calls, tool_calls})
            do_resolve(tool_calls, context, sink)

          {:error, reason} ->
            Logger.error("[Resonance] LLM call failed: #{inspect(reason)}")
            sink.({:error, reason})
        end
      rescue
        e ->
          sink.({:error, {:internal_error, Exception.message(e)}})
      catch
        :exit, reason ->
          sink.({:error, {:task_exit, inspect(reason)}})
      end
    end)

    :ok
  end

  @doc """
  Re-resolve existing tool calls without going back to the LLM.

  Used by refresh flows — the caller has already stored the tool calls
  from a prior `run/3`, and wants fresh data against the same intents.
  Spawns a supervised task; delivers the same `:component_ready` and
  `:done` events as `run/3`.
  """
  @spec resolve([Resonance.LLM.ToolCall.t()], map(), sink()) :: :ok
  def resolve(tool_calls, context, sink) when is_function(sink, 1) do
    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      try do
        do_resolve(tool_calls, context, sink)
      rescue
        e ->
          sink.({:error, {:internal_error, Exception.message(e)}})
      catch
        :exit, reason ->
          sink.({:error, {:task_exit, inspect(reason)}})
      end
    end)

    :ok
  end

  # Parallel resolution with stable IDs, shared by run/3 and resolve/3.
  # Uses async_stream_nolink so a single crashing primitive doesn't bring
  # down the pipeline task — the crash becomes an error Renderable and the
  # rest of the batch still resolves.
  defp do_resolve(tool_calls, context, sink) do
    Task.Supervisor.async_stream_nolink(
      Resonance.TaskSupervisor,
      Enum.with_index(tool_calls),
      fn {call, idx} ->
        renderable = Composer.resolve_one(call, context)
        # Deterministic ID: same tool calls always produce same DOM IDs,
        # so LiveView can re-render in place instead of remounting.
        %{renderable | id: "#{call.name}-#{idx}"}
      end,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, renderable} ->
        sink.({:component_ready, renderable})

      {:exit, :timeout} ->
        sink.({:component_ready, Renderable.error("unknown", :timeout)})

      {:exit, reason} ->
        # A single primitive crashed. Surface it as an error Renderable so
        # the rest of the batch still resolves. The outer try/rescue in
        # run/3 and resolve/3 handles pipeline-level crashes.
        sink.({:component_ready, Renderable.error("unknown", {:crashed, reason})})
    end)

    sink.(:done)
  end
end
