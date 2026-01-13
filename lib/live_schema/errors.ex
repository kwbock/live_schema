defmodule LiveSchema.CompileError do
  @moduledoc """
  Exception raised when there's a compile-time issue with a LiveSchema definition.

  This error is raised during compilation when the schema DSL is used incorrectly.

  ## Fields

  - `:field` - The field name that caused the error (if applicable)
  - `:message` - A description of what went wrong
  - `:file` - The source file where the error occurred
  - `:line` - The line number where the error occurred

  ## Example

      ** (LiveSchema.CompileError) Invalid field definition for :name
          Expected type specification, got: "string"
          at lib/my_app/state.ex:15

  """

  defexception [:field, :message, :file, :line]

  @impl true
  def message(%__MODULE__{field: nil, message: msg, file: file, line: line}) do
    location = format_location(file, line)
    "#{msg}#{location}"
  end

  def message(%__MODULE__{field: field, message: msg, file: file, line: line}) do
    location = format_location(file, line)
    "Invalid field definition for #{inspect(field)}\n    #{msg}#{location}"
  end

  defp format_location(nil, nil), do: ""
  defp format_location(file, nil), do: "\n    at #{file}"
  defp format_location(nil, line), do: "\n    at line #{line}"
  defp format_location(file, line), do: "\n    at #{file}:#{line}"
end

defmodule LiveSchema.TypeError do
  @moduledoc """
  Exception raised when a runtime type mismatch occurs.

  This error is raised when validation is enabled and a value doesn't
  match the expected type for a field.

  ## Fields

  - `:field` - The field name that has the type mismatch
  - `:expected` - Description of the expected type
  - `:got` - Description of what was actually received
  - `:hint` - Optional suggestion for fixing the error
  - `:path` - The full path to the field (for nested structs)

  ## Example

      ** (LiveSchema.TypeError) Type mismatch for field :status
          Expected: :all | :active | :archived
          Got: "all" (string)

          Hint: Did you forget to convert the string from form params?
          Use String.to_existing_atom/1 or pass atoms directly.

  """

  defexception [:field, :expected, :got, :hint, :path]

  @impl true
  def message(%__MODULE__{} = error) do
    path_str =
      case error.path do
        nil -> ""
        [] -> ""
        path -> " (at path: #{format_path(path)})"
      end

    hint_str =
      case error.hint do
        nil -> ""
        hint -> "\n\n    Hint: #{hint}"
      end

    """
    Type mismatch for field #{inspect(error.field)}#{path_str}
        Expected: #{error.expected}
        Got: #{error.got}#{hint_str}
    """
  end

  defp format_path(path) when is_list(path) do
    path |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  @doc """
  Creates a TypeError with a hint based on common mistakes.
  """
  def with_hint(error, :string_to_atom) do
    %{
      error
      | hint:
          "Did you forget to convert the string from form params?\n    Use String.to_existing_atom/1 or pass atoms directly."
    }
  end

  def with_hint(error, :nil_value) do
    %{
      error
      | hint:
          "The value is nil but the field is not nullable.\n    Use {:nullable, type} if nil is a valid value."
    }
  end

  def with_hint(error, :wrong_struct) do
    %{
      error
      | hint:
          "Make sure you're passing the correct struct type.\n    Check your data transformations."
    }
  end

  def with_hint(error, _), do: error
end

defmodule LiveSchema.ActionError do
  @moduledoc """
  Exception raised when an invalid reducer action is dispatched.

  This error occurs when trying to apply an action that doesn't
  exist in the schema's reducers.

  ## Fields

  - `:action` - The action that was attempted
  - `:available_actions` - List of valid actions for this schema
  - `:hint` - Optional suggestion for fixing the error
  - `:schema` - The schema module

  ## Example

      ** (LiveSchema.ActionError) Unknown action :selct_post
          Available actions: [:select_post, :load_posts, :reset_filter]

          Hint: Did you mean :select_post?

  """

  defexception [:action, :available_actions, :hint, :schema]

  @impl true
  def message(%__MODULE__{} = error) do
    actions_str =
      error.available_actions
      |> Enum.map(&inspect/1)
      |> Enum.join(", ")

    hint_str =
      case error.hint do
        nil -> maybe_suggest_action(error.action, error.available_actions)
        hint -> "\n\n    Hint: #{hint}"
      end

    schema_str =
      case error.schema do
        nil -> ""
        schema -> " for #{inspect(schema)}"
      end

    """
    Unknown action #{inspect(error.action)}#{schema_str}
        Available actions: [#{actions_str}]#{hint_str}
    """
  end

  defp maybe_suggest_action(action, available) when is_atom(action) do
    action_string = to_string(action)

    suggestion =
      available
      |> Enum.map(fn a -> {a, String.jaro_distance(to_string(a), action_string)} end)
      |> Enum.filter(fn {_, score} -> score > 0.8 end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> List.first()

    case suggestion do
      {suggested, _} -> "\n\n    Hint: Did you mean #{inspect(suggested)}?"
      nil -> ""
    end
  end

  defp maybe_suggest_action(_, _), do: ""
end

defmodule LiveSchema.ValidationError do
  @moduledoc """
  Structured validation error for fields.

  Contains detailed information about validation failures that can be
  formatted for different output formats (human-readable, JSON, forms).

  ## Fields

  - `:field` - The field name that failed validation
  - `:value` - The value that was invalid
  - `:errors` - List of `{type, message}` tuples describing failures
  - `:path` - Full path to the field (for nested structs)

  ## Example

      %LiveSchema.ValidationError{
        field: :email,
        value: "invalid",
        errors: [
          {:format, "must match pattern ~r/@/"},
          {:length, "must be at least 5 characters"}
        ],
        path: [:user, :email]
      }

  """

  defexception [:field, :value, :errors, :path]

  @type t :: %__MODULE__{
          field: atom(),
          value: any(),
          errors: [{atom(), String.t()}],
          path: [atom()] | nil
        }

  @impl true
  def message(%__MODULE__{} = error) do
    path_str = format_path(error.path, error.field)

    errors_str =
      error.errors
      |> Enum.map(fn {type, msg} -> "    - #{type}: #{msg}" end)
      |> Enum.join("\n")

    """
    Validation failed for #{path_str}
        Value: #{inspect(error.value)}
        Errors:
    #{errors_str}
    """
  end

  defp format_path(nil, field), do: inspect(field)
  defp format_path([], field), do: inspect(field)

  defp format_path(path, field) do
    full_path = path ++ [field]
    full_path |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  @doc """
  Converts the validation error to a human-readable string.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = error) do
    message(error)
  end

  @doc """
  Converts the validation error to a JSON-serializable map.

  Useful for API responses.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = error) do
    %{
      field: error.field,
      path: error.path || [],
      errors:
        Enum.map(error.errors, fn {type, msg} ->
          %{type: type, message: msg}
        end)
    }
  end

  @doc """
  Formats errors for Phoenix form integration.

  Returns a keyword list suitable for use with Phoenix.HTML.Form.
  """
  @spec format_for_form([t()]) :: keyword()
  def format_for_form(errors) when is_list(errors) do
    Enum.flat_map(errors, fn %__MODULE__{field: field, errors: errs} ->
      messages = Enum.map(errs, fn {_type, msg} -> msg end)

      case messages do
        [single] -> [{field, single}]
        multiple -> [{field, Enum.join(multiple, "; ")}]
      end
    end)
  end
end
