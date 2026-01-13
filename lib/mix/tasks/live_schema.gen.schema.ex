defmodule Mix.Tasks.LiveSchema.Gen.Schema do
  @shortdoc "Generates a LiveSchema state module"

  @moduledoc """
  Generates a LiveSchema state module.

      $ mix live_schema.gen.schema Posts posts:list selected:nullable loading:boolean

  The first argument is the module name (will be appended to your app's namespace).
  The remaining arguments are field definitions in the format `name:type`.

  ## Field Types

  - `string` - String type
  - `integer` - Integer type
  - `float` - Float type
  - `boolean` - Boolean type
  - `atom` - Atom type
  - `list` - Generic list
  - `map` - Generic map
  - `nullable` - Nullable type (wraps previous or defaults to :any)

  ## Examples

      # Generate a basic schema
      $ mix live_schema.gen.schema UserProfile name:string email:string age:integer

      # Generate with list and nullable types
      $ mix live_schema.gen.schema Posts posts:list selected:nullable loading:boolean

      # Specify a custom namespace
      $ mix live_schema.gen.schema MyApp.States.Posts posts:list

  ## Options

  - `--no-reducers` - Don't generate example reducers
  - `--context` - The context module (default: derived from app name)

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, parsed, _} = OptionParser.parse(args, switches: [
      no_reducers: :boolean,
      context: :string
    ])

    case parsed do
      [] ->
        Mix.raise("Expected module name as first argument")

      [module_name | field_args] ->
        fields = parse_fields(field_args)
        context = opts[:context] || default_context()
        generate_schema(module_name, fields, context, opts)
    end
  end

  defp parse_fields(args) do
    Enum.map(args, fn arg ->
      case String.split(arg, ":") do
        [name, type] ->
          {String.to_atom(name), parse_type(type)}

        [name] ->
          {String.to_atom(name), :any}

        _ ->
          Mix.raise("Invalid field format: #{arg}. Expected name:type")
      end
    end)
  end

  defp parse_type("string"), do: :string
  defp parse_type("integer"), do: :integer
  defp parse_type("float"), do: :float
  defp parse_type("boolean"), do: :boolean
  defp parse_type("atom"), do: :atom
  defp parse_type("list"), do: {:list, :any}
  defp parse_type("map"), do: :map
  defp parse_type("nullable"), do: {:nullable, :any}
  defp parse_type(other), do: String.to_atom(other)

  defp default_context do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
  end

  defp generate_schema(module_name, fields, context, opts) do
    full_module = Module.concat([context, module_name])
    file_path = module_to_path(full_module)

    content = generate_content(full_module, fields, opts)

    Mix.Generator.create_file(file_path, content)

    Mix.shell().info("""

    Generated LiveSchema module at #{file_path}

    To use in your LiveView:

        defmodule #{context}Web.#{module_name}Live do
          use #{context}Web, :live_view
          use LiveSchema.View, schema: #{full_module}

          def mount(_params, _session, socket) do
            {:ok, init_state(socket)}
          end
        end
    """)
  end

  defp module_to_path(module) do
    path =
      module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> Path.join()

    "lib/#{path}.ex"
  end

  defp generate_content(module, fields, opts) do
    field_definitions = generate_field_definitions(fields)
    reducer_definitions = if opts[:no_reducers], do: "", else: generate_example_reducers(fields)

    """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      State module for managing #{module |> Module.split() |> List.last()} state.
      \"\"\"

      use LiveSchema

      schema do
    #{field_definitions}
      end
    #{reducer_definitions}
    end
    """
  end

  defp generate_field_definitions(fields) do
    fields
    |> Enum.map(fn {name, type} ->
      default = default_for_type(type)
      type_str = format_type(type)
      "    field :#{name}, #{type_str}#{default}"
    end)
    |> Enum.join("\n")
  end

  defp format_type(:string), do: ":string"
  defp format_type(:integer), do: ":integer"
  defp format_type(:float), do: ":float"
  defp format_type(:boolean), do: ":boolean"
  defp format_type(:atom), do: ":atom"
  defp format_type(:map), do: ":map"
  defp format_type(:any), do: ":any"
  defp format_type({:list, inner}), do: "{:list, #{format_type(inner)}}"
  defp format_type({:nullable, inner}), do: "{:nullable, #{format_type(inner)}}"
  defp format_type(other), do: inspect(other)

  defp default_for_type(:boolean), do: ", default: false"
  defp default_for_type(:integer), do: ", default: 0"
  defp default_for_type({:list, _}), do: ", default: []"
  defp default_for_type({:nullable, _}), do: ""
  defp default_for_type(:string), do: ", default: \"\""
  defp default_for_type(_), do: ""

  defp generate_example_reducers(_fields) do
    # Generate a simple reset reducer
    """

      # Example reducers - customize as needed

      reducer :reset do
        new()
      end
    """
  end
end
