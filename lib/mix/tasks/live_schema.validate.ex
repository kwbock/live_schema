defmodule Mix.Tasks.LiveSchema.Validate do
  @shortdoc "Validates all LiveSchema modules in the project"

  @moduledoc """
  Validates all LiveSchema modules in the project compile correctly.

      $ mix live_schema.validate

  This task will:

  1. Find all modules that `use LiveSchema`
  2. Verify they compile without errors
  3. Check that all field types are valid
  4. Report any issues found

  ## Options

  - `--verbose` - Print detailed information about each module

  ## Examples

      $ mix live_schema.validate
      $ mix live_schema.validate --verbose

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [verbose: :boolean])
    verbose = opts[:verbose] || false

    Mix.Task.run("compile", [])

    modules = find_live_schema_modules()

    if Enum.empty?(modules) do
      Mix.shell().info("No LiveSchema modules found.")
    else
      Mix.shell().info("Found #{length(modules)} LiveSchema module(s)\n")

      results =
        Enum.map(modules, fn module ->
          validate_module(module, verbose)
        end)

      errors = Enum.filter(results, &match?({:error, _, _}, &1))
      successes = Enum.filter(results, &match?({:ok, _}, &1))

      Mix.shell().info("\n#{IO.ANSI.bright()}Summary:#{IO.ANSI.reset()}")
      Mix.shell().info("  #{IO.ANSI.green()}Passed: #{length(successes)}#{IO.ANSI.reset()}")

      if length(errors) > 0 do
        Mix.shell().info("  #{IO.ANSI.red()}Failed: #{length(errors)}#{IO.ANSI.reset()}")
        System.halt(1)
      end
    end
  end

  defp find_live_schema_modules do
    # Get all compiled modules
    {:ok, modules} = :application.get_key(Mix.Project.config()[:app], :modules)

    modules
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__live_schema__, 1)
    end)
  rescue
    _ -> []
  end

  defp validate_module(module, verbose) do
    if verbose do
      Mix.shell().info("Validating #{inspect(module)}...")
    end

    try do
      # Check fields exist
      fields = module.__live_schema__(:fields)

      # Validate each field's type
      Enum.each(fields, fn field ->
        info = module.__live_schema__({:field, field})
        validate_type(info.type)
      end)

      # Try to create a new instance
      _instance = module.new()

      if verbose do
        Mix.shell().info("  #{IO.ANSI.green()}OK#{IO.ANSI.reset()} - #{length(fields)} fields")
      else
        Mix.shell().info("  #{IO.ANSI.green()}[OK]#{IO.ANSI.reset()} #{inspect(module)}")
      end

      {:ok, module}
    rescue
      e ->
        Mix.shell().info("  #{IO.ANSI.red()}[FAIL]#{IO.ANSI.reset()} #{inspect(module)}")
        Mix.shell().info("    Error: #{Exception.message(e)}")
        {:error, module, e}
    end
  end

  defp validate_type(:string), do: :ok
  defp validate_type(:integer), do: :ok
  defp validate_type(:float), do: :ok
  defp validate_type(:boolean), do: :ok
  defp validate_type(:atom), do: :ok
  defp validate_type(:any), do: :ok
  defp validate_type(:map), do: :ok
  defp validate_type(:list), do: :ok
  defp validate_type({:list, inner}), do: validate_type(inner)

  defp validate_type({:map, k, v}),
    do:
      (
        validate_type(k)
        validate_type(v)
      )

  defp validate_type({:enum, values}) when is_list(values), do: :ok
  defp validate_type({:struct, module}) when is_atom(module), do: :ok
  defp validate_type({:tuple, types}) when is_list(types), do: Enum.each(types, &validate_type/1)
  defp validate_type(other), do: raise("Invalid type: #{inspect(other)}")
end
