defmodule Resonance.Composer do
  @moduledoc """
  Orchestrates tool calls into resolved, renderable components.

  Takes normalized tool calls from the LLM and dispatches each to its
  registered primitive for data resolution and presentation mapping.
  """

  require Logger
  alias Resonance.{Registry, Renderable, Result}

  @doc """
  Compose all tool calls into a list of Renderables.

  Resolves primitives in parallel via `Task.Supervisor.async_stream_nolink`
  and returns all results once complete.
  """
  @spec compose([Resonance.LLM.ToolCall.t()], map()) ::
          {:ok, [Renderable.t()]} | {:error, term()}
  def compose(tool_calls, context) do
    renderables =
      Task.Supervisor.async_stream_nolink(
        Resonance.TaskSupervisor,
        tool_calls,
        fn call -> resolve_one(call, context) end,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, renderable} -> renderable
        {:exit, :timeout} -> Renderable.error("unknown", :timeout)
      end)

    {:ok, renderables}
  end

  @doc """
  Stream composed components to a process as they resolve.

  Sends `{:resonance, {:component_ready, renderable}}` for each resolved
  component and `{:resonance, :done}` when all are complete.
  """
  @spec compose_stream([Resonance.LLM.ToolCall.t()], map(), pid()) :: :ok
  def compose_stream(tool_calls, context, pid) do
    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      Task.Supervisor.async_stream_nolink(
        Resonance.TaskSupervisor,
        tool_calls,
        fn call -> resolve_one(call, context) end,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.each(fn
        {:ok, renderable} ->
          send(pid, {:resonance, {:component_ready, renderable}})

        {:exit, :timeout} ->
          send(pid, {:resonance, {:component_ready, Renderable.error("unknown", :timeout)}})
      end)

      send(pid, {:resonance, :done})
    end)

    :ok
  end

  @doc """
  Resolve a single tool call into a Renderable.

  Calls the primitive's `resolve/2` to get a `Result`, then passes
  it to the presenter (from context, default: `Resonance.Presenters.Default`)
  to produce a `Renderable`.
  """
  def resolve_one(%{name: name, arguments: arguments}, context) do
    Logger.info("[Resonance] Resolving primitive: #{name} with #{inspect(Map.keys(arguments))}")

    metadata = %{primitive: name}

    :telemetry.span([:resonance, :primitive, :resolve], metadata, fn ->
      result =
        case Registry.get(name) do
          nil ->
            Logger.warning("[Resonance] Unknown primitive: #{name}")
            Renderable.error(name, {:unknown_primitive, name})

          primitive_module ->
            case primitive_module.resolve(arguments, context) do
              {:ok, %Result{} = result} ->
                Logger.info(
                  "[Resonance] #{name} resolved: kind=#{result.kind} rows=#{length(result.data)}"
                )

                presenter = context[:presenter] || Resonance.Presenters.Default
                presenter.present(result, context)

              {:error, reason} ->
                Logger.warning(
                  "[Resonance] #{name} failed: #{inspect(reason)} — args: #{inspect(arguments)}"
                )

                Renderable.error(name, reason)
            end
        end

      {result, Map.put(metadata, :renderable, result)}
    end)
  end
end
