defmodule Resonance.Composer do
  @moduledoc """
  Resolves tool calls into renderable components.

  `resolve_one/2` is the core primitive: take a tool call, dispatch to
  its registered primitive, produce a `Renderable`. `compose/2` runs a
  batch of tool calls in parallel and returns the results.

  The streaming / event-driven path — with stable IDs and sink-based
  delivery — lives in `Resonance.Pipeline`, which is the canonical entry
  point for both the public `Resonance.generate_stream/3` API and the
  in-library `Resonance.Live.Report` surface.
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
                renderable = presenter.present(result, context)
                # Stamp the source Result onto the Renderable as an
                # introspection-only paper trail. Widgets must not read it
                # at runtime — see Resonance.Renderable docs.
                %{renderable | result: result}

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
