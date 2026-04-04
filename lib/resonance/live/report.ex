defmodule Resonance.Live.Report do
  @moduledoc """
  Drop-in LiveView component for Resonance report generation.

  ## Usage

      <.live_component
        module={Resonance.Live.Report}
        id="resonance-report"
        resolver={MyApp.DataResolver}
        current_user={@current_user}
      />

  No parent LiveView wiring needed — the component handles the full
  lifecycle internally via `send_update/3`.
  """

  use Phoenix.LiveComponent

  alias Resonance.{Composer, Layout, LLM, Registry, Renderable}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       components: [],
       loading: false,
       prompt: "",
       error: nil,
       tool_calls: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign_new(:resolver, fn -> assigns[:resolver] end)
      |> assign_new(:current_user, fn -> assigns[:current_user] end)
      |> assign_new(:components, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:prompt, fn -> "" end)
      |> assign_new(:error, fn -> nil end)

    # Handle streaming: individual component arrivals
    # If a renderable with the same ID exists, replace it in-place and
    # push new data to the chart hook via event (bypasses phx-update="ignore").
    # Otherwise append (initial generation).
    socket =
      case assigns[:resonance_component] do
        %Renderable{} = renderable ->
          existing = socket.assigns.components

          if Enum.any?(existing, &(&1.id == renderable.id)) do
            updated = Enum.map(existing, fn r ->
              if r.id == renderable.id, do: renderable, else: r
            end)

            socket = assign(socket, :components, updated)
            push_chart_update(socket, renderable)
          else
            assign(socket, :components, existing ++ [renderable])
          end

        _ ->
          socket
      end

    # Handle streaming: store tool calls for refresh
    socket =
      case assigns[:resonance_tool_calls] do
        calls when is_list(calls) -> assign(socket, tool_calls: calls)
        _ -> socket
      end

    # Handle streaming: done signal
    socket =
      case assigns[:resonance_done] do
        true -> assign(socket, loading: false)
        _ -> socket
      end

    # Handle batch result (error path fallback)
    socket =
      case assigns[:resonance_result] do
        {:error, reason} -> assign(socket, error: reason, loading: false)
        _ -> socket
      end

    # Handle prompt set from parent (e.g. clicking a suggestion)
    socket =
      case assigns[:set_prompt] do
        prompt when is_binary(prompt) ->
          socket
          |> assign(:prompt, prompt)
          |> push_event("resonance:set-prompt", %{prompt: prompt})

        _ ->
          socket
      end

    # Handle regenerate from parent (full LLM call + resolve)
    socket =
      case assigns[:regenerate] do
        prompt when is_binary(prompt) and byte_size(prompt) > 0 ->
          start_generation(socket, prompt)

        _ ->
          socket
      end

    # Handle refresh from parent (re-resolve same tool calls, no LLM)
    socket =
      case assigns[:refresh] do
        true when socket.assigns.tool_calls != nil ->
          refresh_data(socket)

        _ ->
          socket
      end

    # Allow resolver to be updated
    socket =
      if assigns[:resolver], do: assign(socket, :resolver, assigns.resolver), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) when byte_size(prompt) > 0 do
    {:noreply, start_generation(socket, prompt)}
  end

  def handle_event("generate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, components: [], loading: false, prompt: "", error: nil)}
  end

  defp start_generation(socket, prompt) do
    socket = assign(socket, loading: true, components: [], prompt: prompt, error: nil)

    context = %{
      resolver: socket.assigns.resolver,
      current_user: socket.assigns[:current_user]
    }

    component_id = socket.assigns.id
    lv_pid = self()

    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      try do
        case LLM.chat(prompt, Registry.all_schemas(), context) do
          {:ok, tool_calls} ->
            # Store tool calls for future refreshes (no LLM re-call needed)
            send_update(lv_pid, __MODULE__,
              id: component_id,
              resonance_tool_calls: tool_calls
            )

            resolve_and_stream(tool_calls, context, lv_pid, component_id)

          {:error, reason} ->
            send_update(lv_pid, __MODULE__,
              id: component_id,
              resonance_result: {:error, reason}
            )
        end
      rescue
        e ->
          send_update(lv_pid, __MODULE__,
            id: component_id,
            resonance_result: {:error, {:internal_error, Exception.message(e)}}
          )
      catch
        :exit, reason ->
          send_update(lv_pid, __MODULE__,
            id: component_id,
            resonance_result: {:error, {:task_exit, inspect(reason)}}
          )
      end
    end)

    socket
  end

  defp refresh_data(socket) do
    socket = assign(socket, loading: true, error: nil)

    context = %{
      resolver: socket.assigns.resolver,
      current_user: socket.assigns[:current_user]
    }

    tool_calls = socket.assigns.tool_calls
    component_id = socket.assigns.id
    lv_pid = self()

    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      try do
        resolve_and_stream(tool_calls, context, lv_pid, component_id)
      rescue
        e ->
          send_update(lv_pid, __MODULE__,
            id: component_id,
            resonance_result: {:error, {:internal_error, Exception.message(e)}}
          )
      end
    end)

    socket
  end

  defp resolve_and_stream(tool_calls, context, lv_pid, component_id) do
    tool_calls
    |> Enum.with_index()
    |> Task.async_stream(
      fn {call, idx} ->
        renderable = Composer.resolve_one(call, context)
        # Deterministic ID: same tool calls always produce same DOM IDs
        stable_id = "#{call.name}-#{idx}"
        %{renderable | id: stable_id}
      end,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, renderable} ->
        send_update(lv_pid, __MODULE__,
          id: component_id,
          resonance_component: renderable
        )

      {:exit, :timeout} ->
        send_update(lv_pid, __MODULE__,
          id: component_id,
          resonance_component: Renderable.error("unknown", :timeout)
        )
    end)

    send_update(lv_pid, __MODULE__, id: component_id, resonance_done: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="resonance-report" id={@id}>
      <form phx-submit="generate" phx-target={@myself}>
        <div class="resonance-prompt-container">
          <input
            type="text"
            name="prompt"
            id={"#{@id}-prompt"}
            value={@prompt}
            placeholder="What would you like to see?"
            class="resonance-prompt-input"
            disabled={@loading}
            autocomplete="off"
            phx-hook="ResonancePromptInput"
          />
          <button type="submit" class="resonance-generate-btn" disabled={@loading}>
            {if @loading, do: "Generating...", else: "Generate"}
          </button>
        </div>
      </form>

      <div :if={@error} class="resonance-error-banner">
        <p>Something went wrong: {format_error(@error)}</p>
      </div>

      <div :if={@loading} class="resonance-loading">
        <div class="resonance-loading-indicator">Composing your report...</div>
      </div>

      <div :if={@components != []} class="resonance-components">
        <%= for component <- Layout.order(@components) do %>
          <div class="resonance-component-wrapper">
            {render_component(component)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_component(%Renderable{status: :error} = r) do
    assigns = %{error: r.error}

    ~H"""
    <div class="resonance-component resonance-error">
      <p class="resonance-error-text">{format_error(@error)}</p>
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props, id: id}) do
    assigns = %{__changed__: nil, props: props, renderable_id: id}
    component.render(assigns)
  end

  defp render_component(_), do: nil

  defp push_chart_update(socket, %Renderable{} = renderable) do
    case chart_dom_id(renderable) do
      nil -> socket
      dom_id ->
        push_event(socket, "resonance:update-chart", %{
          id: dom_id,
          data: renderable.props[:data] || renderable.props["data"] || []
        })
    end
  end

  defp chart_dom_id(%Renderable{component: comp, id: id}) do
    case comp do
      Resonance.Components.BarChart -> "resonance-bar-#{id}"
      Resonance.Components.LineChart -> "resonance-line-#{id}"
      Resonance.Components.PieChart -> "resonance-pie-#{id}"
      _ -> nil
    end
  end

  defp format_error({:api_error, status, %{"error" => %{"message" => msg}}}),
    do: "API error (#{status}): #{msg}"

  defp format_error({:api_error, status, _}),
    do: "API error (#{status})"

  defp format_error({:request_failed, _}),
    do: "Could not reach the LLM provider. Check your network and API key."

  defp format_error({:unknown_primitive, name}),
    do: "Unknown analysis type: #{name}"

  defp format_error({:unsupported_query, dataset}),
    do: "The query combination for \"#{dataset}\" is not supported yet."

  defp format_error({:query_failed, msg}) when is_binary(msg),
    do: "Data query failed: #{msg}"

  defp format_error({:invalid_field, field, msg}),
    do: "Invalid #{field}: #{msg}"

  defp format_error({:internal_error, msg}),
    do: "Internal error: #{msg}"

  defp format_error({:task_exit, msg}),
    do: "Report generation failed unexpectedly: #{msg}"

  defp format_error(error), do: inspect(error)
end
