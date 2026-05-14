defmodule Mix.Tasks.ResonanceDemo.PlannerEval.Real do
  @moduledoc """
  Run the CRM planner eval against the configured real LLM provider.

  This task may call an external paid API. It refuses to run unless explicitly
  allowed:

      mix resonance_demo.planner_eval.real --allow-paid

  Useful options:

      --out PATH                 Markdown report path
      --json PATH                JSON report path
      --provider anthropic       Override configured provider
      --provider openai          Override configured provider
      --model MODEL              Override configured model
      --limit N                  Run the first N prompts
      --max-validation-retries N Planner validation retries, default 1

  You can also set `RESONANCE_ALLOW_PAID_LLM_EVAL=1` instead of passing
  `--allow-paid`.
  """

  use Mix.Task

  alias ResonanceDemo.PlannerEval

  @shortdoc "Run CRM planner eval against the real configured LLM provider"

  @switches [
    allow_paid: :boolean,
    out: :string,
    json: :string,
    provider: :string,
    model: :string,
    limit: :integer,
    max_validation_retries: :integer,
    help: :boolean
  ]

  @impl true
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        Mix.raise("Invalid options: #{inspect(invalid)}")

      not paid_eval_allowed?(opts) ->
        Mix.raise("""
        Refusing to run real-provider planner eval because it may call a paid external API.

        Re-run with:

            mix resonance_demo.planner_eval.real --allow-paid

        or set:

            RESONANCE_ALLOW_PAID_LLM_EVAL=1
        """)

      true ->
        run_eval(opts)
    end
  end

  defp run_eval(opts) do
    Mix.Task.run("app.start")

    prompt_set =
      PlannerEval.prompts()
      |> maybe_limit(opts[:limit])

    provider = parse_provider(opts[:provider])

    eval_opts =
      []
      |> put_if_present(:provider, provider)
      |> put_if_present(:api_key, api_key_for(provider))
      |> put_if_present(:model, opts[:model])
      |> Keyword.put(:max_validation_retries, opts[:max_validation_retries] || 1)

    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    evaluation = PlannerEval.evaluate_real(Keyword.put(eval_opts, :prompts, prompt_set))
    finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

    report_context = %{
      started_at: started_at,
      finished_at: finished_at,
      provider: provider_label(eval_opts),
      model: model_label(eval_opts),
      prompt_count: length(prompt_set)
    }

    markdown = markdown_report(evaluation, report_context)
    json = json_report(evaluation, report_context)

    out_path = opts[:out] || default_markdown_path()
    json_path = opts[:json]

    write_report(out_path, markdown)
    if json_path, do: write_report(json_path, Jason.encode!(json, pretty: true))

    Mix.shell().info(summary_line(evaluation, out_path, json_path))
  end

  defp paid_eval_allowed?(opts) do
    opts[:allow_paid] || System.get_env("RESONANCE_ALLOW_PAID_LLM_EVAL") == "1"
  end

  defp maybe_limit(prompt_set, nil), do: prompt_set

  defp maybe_limit(prompt_set, limit) when is_integer(limit) and limit > 0,
    do: Enum.take(prompt_set, limit)

  defp maybe_limit(_prompt_set, limit),
    do: Mix.raise("--limit must be a positive integer, got #{inspect(limit)}")

  defp parse_provider(nil), do: nil
  defp parse_provider("anthropic"), do: :anthropic
  defp parse_provider("openai"), do: :openai

  defp parse_provider(provider) do
    Mix.raise("--provider must be anthropic or openai, got #{inspect(provider)}")
  end

  defp api_key_for(:anthropic),
    do: System.get_env("ANTHROPIC_API_KEY") || System.get_env("RESONANCE_API_KEY")

  defp api_key_for(:openai),
    do: System.get_env("OPENAI_API_KEY") || System.get_env("RESONANCE_API_KEY")

  defp api_key_for(nil), do: nil

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp provider_label(eval_opts) do
    eval_opts[:provider] || Application.get_env(:resonance, :provider) || "configured provider"
  end

  defp model_label(eval_opts) do
    eval_opts[:model] || Application.get_env(:resonance, :model) || "configured model"
  end

  defp default_markdown_path do
    Path.join(repo_root(), "docs/design/v3-planner-eval-real-results.md")
  end

  defp repo_root do
    cwd = File.cwd!()

    if Path.basename(cwd) == "resonance_demo" do
      Path.expand("../..", cwd)
    else
      cwd
    end
  end

  defp write_report(path, contents) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp markdown_report(evaluation, context) do
    rows = report_rows(evaluation)

    """
    # v3 Planner Eval Real-Provider Results

    Started: #{DateTime.to_iso8601(context.started_at)}
    Finished: #{DateTime.to_iso8601(context.finished_at)}
    Provider: `#{context.provider}`
    Model: `#{context.model}`
    Prompts: #{context.prompt_count}

    ## Summary

    | Metric | Result |
    | --- | ---: |
    | Total prompts | #{evaluation.summary.total} |
    | Valid plans | #{evaluation.summary.valid_plans} |
    | Compiled workspaces | #{evaluation.summary.compiled} |
    | Invalid plans | #{evaluation.summary.invalid_plans} |
    | Compile failures | #{evaluation.summary.compile_failed} |
    | Retried | #{evaluation.summary.retried} |
    | Recovered | #{evaluation.summary.recovered} |
    | Invented capability failures | #{evaluation.summary.invented_capability_failures} |
    | Invented pattern failures | #{evaluation.summary.invented_pattern_failures} |
    | Invented primitive failures | #{evaluation.summary.invented_primitive_failures} |
    | Valid plan rate | #{percent(evaluation.summary.valid_plan_rate)} |
    | Compile rate | #{percent(evaluation.summary.compile_rate)} |

    ## Prompt Results

    | Prompt | Status | Attempts | Sections | Primitives | Errors | Retry Errors |
    | --- | --- | ---: | ---: | --- | --- | --- |
    #{Enum.map_join(rows, "\n", &markdown_row/1)}
    """
  end

  defp markdown_row(row) do
    "| #{escape(row.prompt)} | `#{row.status}` | #{row.attempts} | #{row.section_count} | #{escape(Enum.join(row.primitives, ", "))} | #{escape(Enum.join(row.errors, "; "))} | #{escape(Enum.join(row.retry_errors, "; "))} |"
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace("\n", " ")
  end

  defp percent(rate) when is_float(rate), do: "#{Float.round(rate * 100, 1)}%"
  defp percent(rate) when is_integer(rate), do: "#{rate * 100}%"
  defp percent(_rate), do: "n/a"

  defp json_report(evaluation, context) do
    %{
      started_at: DateTime.to_iso8601(context.started_at),
      finished_at: DateTime.to_iso8601(context.finished_at),
      provider: to_string(context.provider),
      model: to_string(context.model),
      summary: evaluation.summary,
      results: report_rows(evaluation)
    }
  end

  defp report_rows(evaluation) do
    Enum.map(evaluation.results, fn result ->
      %{
        id: Map.get(result, :id),
        prompt: result.prompt,
        expectation: Map.get(result, :expectation),
        status: to_string(result.status),
        attempts: result.attempts,
        retried: result.retried?,
        recovered: result.recovered?,
        section_count: result.diagnostics.section_count,
        primitives: result.diagnostics.primitives,
        patterns: Enum.map(result.diagnostics.patterns, &to_string/1),
        invented_capability?: result.diagnostics.invented_capability?,
        invented_pattern?: result.diagnostics.invented_pattern?,
        invented_primitive?: result.diagnostics.invented_primitive?,
        validation_error_codes: Enum.map(result.diagnostics.validation_error_codes, &to_string/1),
        retry_validation_error_codes:
          Enum.map(result.diagnostics.retry_validation_error_codes, &to_string/1),
        retry_errors: retry_error_messages(Map.get(result, :retry_errors, [])),
        errors: error_messages(Map.get(result, :errors))
      }
    end)
  end

  defp retry_error_messages(errors) when is_list(errors) do
    Enum.map(errors, &validation_error_message/1)
  end

  defp retry_error_messages(_errors), do: []

  defp error_messages({:validation_failed, errors}) when is_list(errors) do
    Enum.map(errors, &validation_error_message/1)
  end

  defp error_messages({:renderable_errors, errors}) when is_list(errors) do
    Enum.flat_map(errors, fn
      %{section_id: section_id, error: {:validation_failed, validation_errors}}
      when is_list(validation_errors) ->
        Enum.map(validation_errors, fn error ->
          "#{section_id}: #{validation_error_message(error)}"
        end)

      %{section_id: section_id, error: error} ->
        ["#{section_id}: #{inspect(error)}"]
    end)
  end

  defp error_messages(nil), do: []
  defp error_messages(error), do: [inspect(error)]

  defp validation_error_message(error) do
    path = error.path |> Enum.map_join(".", &to_string/1)
    details = validation_error_details(error)
    "#{path} #{error.code}: #{error.message}#{details}"
  end

  defp validation_error_details(%{details: details}) when map_size(details) > 0 do
    " details=#{inspect(details)}"
  end

  defp validation_error_details(_error), do: ""

  defp summary_line(evaluation, out_path, nil) do
    "Real-provider planner eval complete: #{evaluation.summary.compiled}/#{evaluation.summary.total} compiled. Wrote #{Path.expand(out_path)}"
  end

  defp summary_line(evaluation, out_path, json_path) do
    "Real-provider planner eval complete: #{evaluation.summary.compiled}/#{evaluation.summary.total} compiled. Wrote #{Path.expand(out_path)} and #{Path.expand(json_path)}"
  end
end
