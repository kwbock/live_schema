defmodule LiveSchema.Types do
  @moduledoc """
  Type system for LiveSchema.

  LiveSchema provides a rich type system for defining state field types.
  Types can be validated at runtime for catching errors early in development.

  ## Built-in Types

  ### Primitive Types

  - `:string` - Elixir binary/string
  - `:integer` - Elixir integer
  - `:float` - Elixir float
  - `:boolean` - `true` or `false`
  - `:atom` - Any atom
  - `:any` - Any value (no validation)
  - `:map` - Any map
  - `:list` - Any list

  ### Parameterized Types

  - `{:list, inner_type}` - List of specific type
  - `{:map, key_type, value_type}` - Map with specific key/value types
  - `{:nullable, inner_type}` - Value or `nil`
  - `{:enum, [values]}` - One of the specified values
  - `{:struct, Module}` - A struct of the given module
  - `{:tuple, [types]}` - A tuple with specific element types

  ## Examples

      field :name, :string
      field :count, :integer, default: 0
      field :posts, {:list, {:struct, Post}}
      field :selected, {:nullable, {:struct, Post}}
      field :status, {:enum, [:pending, :active, :done]}
      field :metadata, {:map, :atom, :any}

  """

  @type primitive :: :string | :integer | :float | :boolean | :atom | :any | :map | :list
  @type parameterized ::
          {:list, type_spec()}
          | {:map, type_spec(), type_spec()}
          | {:nullable, type_spec()}
          | {:enum, [any()]}
          | {:struct, module()}
          | {:tuple, [type_spec()]}
  @type type_spec :: primitive() | parameterized()

  @primitives [:string, :integer, :float, :boolean, :atom, :any, :map, :list]

  @doc """
  Validates that a value matches the given type specification.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> LiveSchema.Types.validate_type("hello", :string)
      :ok

      iex> LiveSchema.Types.validate_type(123, :string)
      {:error, "expected string, got integer"}

      iex> LiveSchema.Types.validate_type(:active, {:enum, [:pending, :active]})
      :ok

      iex> LiveSchema.Types.validate_type(nil, {:nullable, :string})
      :ok

  """
  @spec validate_type(any(), type_spec()) :: :ok | {:error, String.t()}
  def validate_type(_value, :any), do: :ok

  def validate_type(value, :string) when is_binary(value), do: :ok
  def validate_type(value, :string), do: {:error, "expected string, got #{type_of(value)}"}

  def validate_type(value, :integer) when is_integer(value), do: :ok
  def validate_type(value, :integer), do: {:error, "expected integer, got #{type_of(value)}"}

  def validate_type(value, :float) when is_float(value), do: :ok
  def validate_type(value, :float), do: {:error, "expected float, got #{type_of(value)}"}

  def validate_type(value, :boolean) when is_boolean(value), do: :ok
  def validate_type(value, :boolean), do: {:error, "expected boolean, got #{type_of(value)}"}

  def validate_type(value, :atom) when is_atom(value), do: :ok
  def validate_type(value, :atom), do: {:error, "expected atom, got #{type_of(value)}"}

  def validate_type(value, :map) when is_map(value), do: :ok
  def validate_type(value, :map), do: {:error, "expected map, got #{type_of(value)}"}

  def validate_type(value, :list) when is_list(value), do: :ok
  def validate_type(value, :list), do: {:error, "expected list, got #{type_of(value)}"}

  # Parameterized types
  def validate_type(nil, {:nullable, _inner_type}), do: :ok
  def validate_type(value, {:nullable, inner_type}), do: validate_type(value, inner_type)

  def validate_type(value, {:list, inner_type}) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate_type(item, inner_type) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "at index #{index}: #{reason}"}}
      end
    end)
  end

  def validate_type(value, {:list, _}), do: {:error, "expected list, got #{type_of(value)}"}

  def validate_type(value, {:map, key_type, value_type}) when is_map(value) do
    value
    |> Enum.reduce_while(:ok, fn {k, v}, :ok ->
      with :ok <- validate_type(k, key_type),
           :ok <- validate_type(v, value_type) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, "map entry error: #{reason}"}}
      end
    end)
  end

  def validate_type(value, {:map, _, _}), do: {:error, "expected map, got #{type_of(value)}"}

  def validate_type(value, {:enum, allowed}) when is_list(allowed) do
    if value in allowed do
      :ok
    else
      allowed_str = allowed |> Enum.map(&inspect/1) |> Enum.join(", ")
      {:error, "expected one of [#{allowed_str}], got #{inspect(value)}"}
    end
  end

  def validate_type(%{__struct__: module} = _value, {:struct, module}), do: :ok

  def validate_type(%{__struct__: actual}, {:struct, expected}) do
    {:error, "expected struct #{inspect(expected)}, got struct #{inspect(actual)}"}
  end

  def validate_type(value, {:struct, expected}) do
    {:error, "expected struct #{inspect(expected)}, got #{type_of(value)}"}
  end

  def validate_type(value, {:tuple, types}) when is_tuple(value) and is_list(types) do
    actual_size = tuple_size(value)
    expected_size = length(types)

    if actual_size != expected_size do
      {:error, "expected tuple of size #{expected_size}, got size #{actual_size}"}
    else
      value
      |> Tuple.to_list()
      |> Enum.zip(types)
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {{item, type}, index}, :ok ->
        case validate_type(item, type) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, "tuple element #{index}: #{reason}"}}
        end
      end)
    end
  end

  def validate_type(value, {:tuple, _}), do: {:error, "expected tuple, got #{type_of(value)}"}

  def validate_type(_value, unknown_type) do
    {:error, "unknown type specification: #{inspect(unknown_type)}"}
  end

  @doc """
  Converts a LiveSchema type spec to Elixir typespec syntax (as AST).

  Used internally for generating @type specifications.

  ## Examples

      iex> LiveSchema.Types.type_to_spec(:string)
      {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}

      iex> LiveSchema.Types.type_to_spec(:integer)
      {:integer, [], []}

  """
  @spec type_to_spec(type_spec()) :: Macro.t()
  def type_to_spec(:string) do
    quote do: String.t()
  end

  def type_to_spec(:integer) do
    quote do: integer()
  end

  def type_to_spec(:float) do
    quote do: float()
  end

  def type_to_spec(:boolean) do
    quote do: boolean()
  end

  def type_to_spec(:atom) do
    quote do: atom()
  end

  def type_to_spec(:any) do
    quote do: any()
  end

  def type_to_spec(:map) do
    quote do: map()
  end

  def type_to_spec(:list) do
    quote do: list()
  end

  def type_to_spec({:nullable, inner_type}) do
    inner = type_to_spec(inner_type)
    quote do: unquote(inner) | nil
  end

  def type_to_spec({:list, inner_type}) do
    inner = type_to_spec(inner_type)
    quote do: [unquote(inner)]
  end

  def type_to_spec({:map, key_type, value_type}) do
    key_spec = type_to_spec(key_type)
    value_spec = type_to_spec(value_type)
    quote do: %{optional(unquote(key_spec)) => unquote(value_spec)}
  end

  def type_to_spec({:enum, values}) when is_list(values) do
    values
    |> Enum.reverse()
    |> Enum.reduce(fn val, acc ->
      quote do: unquote(val) | unquote(acc)
    end)
  end

  def type_to_spec({:struct, module}) when is_atom(module) do
    quote do: unquote(module).t()
  end

  def type_to_spec({:tuple, types}) when is_list(types) do
    type_specs = Enum.map(types, &type_to_spec/1)
    {:{}, [], type_specs}
  end

  def type_to_spec(other) do
    raise ArgumentError, "Cannot convert type spec: #{inspect(other)}"
  end

  @doc """
  Returns whether a type is a primitive type.
  """
  @spec primitive?(type_spec()) :: boolean()
  def primitive?(type) when type in @primitives, do: true
  def primitive?(_), do: false

  @doc """
  Returns the list of all primitive types.
  """
  @spec primitives() :: [primitive()]
  def primitives, do: @primitives

  @doc """
  Returns a default value for the given type.

  Used when no explicit default is provided.
  """
  @spec default_for_type(type_spec()) :: any()
  def default_for_type(:string), do: nil
  def default_for_type(:integer), do: nil
  def default_for_type(:float), do: nil
  def default_for_type(:boolean), do: nil
  def default_for_type(:atom), do: nil
  def default_for_type(:any), do: nil
  def default_for_type(:map), do: nil
  def default_for_type(:list), do: []
  def default_for_type({:list, _}), do: []
  def default_for_type({:map, _, _}), do: %{}
  def default_for_type({:nullable, _}), do: nil
  def default_for_type({:enum, [first | _]}), do: first
  def default_for_type({:struct, _}), do: nil
  def default_for_type({:tuple, _}), do: nil
  def default_for_type(_), do: nil

  # Private helpers

  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_boolean(value), do: "boolean"
  defp type_of(value) when is_atom(value), do: "atom"
  defp type_of(value) when is_list(value), do: "list"
  defp type_of(value) when is_tuple(value), do: "tuple"
  defp type_of(%{__struct__: module}), do: "struct #{inspect(module)}"
  defp type_of(value) when is_map(value), do: "map"
  defp type_of(value) when is_function(value), do: "function"
  defp type_of(value) when is_pid(value), do: "pid"
  defp type_of(value) when is_reference(value), do: "reference"
  defp type_of(value) when is_port(value), do: "port"
  defp type_of(_), do: "unknown"
end
