defmodule LiveSchema.View.Coerce do
  @moduledoc """
  Type coercion utilities for converting string parameters to typed values.

  Used by auto-generated `handle_event/3` callbacks to convert string
  parameters from phx-value-* attributes to the types specified in actions.

  ## Supported Types

  - `:integer` - Parses to integer
  - `:float` - Parses to float
  - `:boolean` - Converts "true"/"false" strings
  - `:atom` - Converts to existing atom (safe)
  - `:string` - Ensures string output
  - `nil` - Passthrough (no coercion)

  ## Examples

      iex> LiveSchema.View.Coerce.coerce("42", :integer)
      42

      iex> LiveSchema.View.Coerce.coerce("3.14", :float)
      3.14

      iex> LiveSchema.View.Coerce.coerce("true", :boolean)
      true

      iex> LiveSchema.View.Coerce.coerce("pending", :atom)
      :pending

      iex> LiveSchema.View.Coerce.coerce(123, :string)
      "123"

      iex> LiveSchema.View.Coerce.coerce("hello", nil)
      "hello"

  """

  @doc """
  Coerces a value to the specified type.

  Returns the coerced value or raises on invalid input.
  """
  @spec coerce(any(), atom() | nil) :: any()
  def coerce(value, :integer) when is_binary(value), do: String.to_integer(value)
  def coerce(value, :integer) when is_integer(value), do: value

  def coerce(value, :float) when is_binary(value), do: String.to_float(value)
  def coerce(value, :float) when is_float(value), do: value
  def coerce(value, :float) when is_integer(value), do: value / 1

  def coerce("true", :boolean), do: true
  def coerce("false", :boolean), do: false
  def coerce(value, :boolean) when is_boolean(value), do: value

  def coerce(value, :atom) when is_binary(value), do: String.to_existing_atom(value)
  def coerce(value, :atom) when is_atom(value), do: value

  def coerce(value, :string), do: to_string(value)

  def coerce(value, nil), do: value
end
