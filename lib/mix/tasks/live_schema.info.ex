defmodule Mix.Tasks.LiveSchema.Info do
  @shortdoc "Prints information about a LiveSchema module"

  @moduledoc """
  Prints detailed information about a LiveSchema module.

      $ mix live_schema.info MyApp.PostsState

  This will display:

  - All defined fields with their types and defaults
  - Embedded structs
  - Available reducers
  - Type specification

  ## Examples

      $ mix live_schema.info MyApp.PostsState
      $ mix live_schema.info MyAppWeb.UserLive.State

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile", [])

    case args do
      [] ->
        Mix.raise("Expected module name as argument")

      [module_str | _] ->
        module = Module.concat([module_str])
        print_info(module)
    end
  end

  defp print_info(module) do
    unless Code.ensure_loaded?(module) do
      Mix.raise("Module #{inspect(module)} not found")
    end

    unless function_exported?(module, :__live_schema__, 1) do
      Mix.raise("Module #{inspect(module)} is not a LiveSchema module")
    end

    fields = module.__live_schema__(:fields)
    embeds = module.__live_schema__(:embeds)
    reducers = module.__live_schema__(:reducers)

    Mix.shell().info("""

    #{IO.ANSI.bright()}LiveSchema: #{inspect(module)}#{IO.ANSI.reset()}

    #{IO.ANSI.cyan()}Fields:#{IO.ANSI.reset()}
    #{format_fields(module, fields)}

    #{IO.ANSI.cyan()}Embeds:#{IO.ANSI.reset()}
    #{format_embeds(embeds)}

    #{IO.ANSI.cyan()}Reducers:#{IO.ANSI.reset()}
    #{format_reducers(reducers)}
    """)
  end

  defp format_fields(module, fields) do
    if Enum.empty?(fields) do
      "  (none)"
    else
      fields
      |> Enum.map(fn field ->
        info = module.__live_schema__({:field, field})
        type_str = format_type(info.type)
        nullable_str = if info[:nullable], do: " | nil", else: ""
        default_str = if info.default, do: " = #{inspect(info.default)}", else: ""
        required_str = if info.required, do: " (required)", else: ""
        redacted_str = if info.redact, do: " [redacted]", else: ""

        "  #{field}: #{type_str}#{nullable_str}#{default_str}#{required_str}#{redacted_str}"
      end)
      |> Enum.join("\n")
    end
  end

  defp format_embeds(embeds) do
    if Enum.empty?(embeds) do
      "  (none)"
    else
      embeds
      |> Enum.map(&"  #{&1}")
      |> Enum.join("\n")
    end
  end

  defp format_reducers(reducers) do
    if Enum.empty?(reducers) do
      "  (none)"
    else
      reducers
      |> Enum.map(&"  #{&1}")
      |> Enum.join("\n")
    end
  end

  defp format_type({:list, inner}), do: "[#{format_type(inner)}]"
  defp format_type({:enum, values}), do: Enum.join(values, " | ")
  defp format_type({:struct, mod}), do: "%#{inspect(mod)}{}"
  defp format_type({:map, k, v}), do: "%{#{format_type(k)} => #{format_type(v)}}"
  defp format_type(type), do: to_string(type)
end
