defmodule Resonance.Presenter do
  @moduledoc """
  Behaviour for mapping resolved data to UI components.

  The Presenter is the developer-controlled layer between semantic truth
  (a `Resonance.Result`) and visual rendering (a `Resonance.Renderable`).

  The library ships `Resonance.Presenters.Default` which uses ApexCharts
  components. Apps can implement their own presenter to use any chart
  library, component system, or brand guidelines.

  ## Example

      defmodule MyApp.Presenters.Custom do
        @behaviour Resonance.Presenter

        @impl true
        def present(%Resonance.Result{kind: :distribution} = result, _context) do
          # Use a treemap instead of a pie chart
          Resonance.Renderable.ready(
            "show_distribution",
            MyApp.Components.Treemap,
            %{title: result.title, data: result.data}
          )
        end

        # Delegate everything else to the default
        def present(result, context) do
          Resonance.Presenters.Default.present(result, context)
        end
      end

  ## Usage

      <.live_component
        module={Resonance.Live.Report}
        id="report"
        resolver={MyResolver}
        presenter={MyApp.Presenters.Custom}
      />
  """

  @doc """
  Map a resolved Result to a Renderable for display.
  """
  @callback present(result :: Resonance.Result.t(), context :: map()) ::
              Resonance.Renderable.t()
end
