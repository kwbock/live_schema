defmodule LiveSchema.Changeset do
  @moduledoc """
  Changeset-style API for making multiple changes to state.

  Provides a way to accumulate changes, validate them together,
  and apply them atomically.

  ## Usage

      state
      |> LiveSchema.change()
      |> LiveSchema.put(:name, "New Name")
      |> LiveSchema.put(:count, 5)
      |> LiveSchema.validate()
      |> LiveSchema.apply()

  ## Working with the Changeset

      changeset = LiveSchema.change(state)

      # Check if there are changes
      changeset.changes
      # => %{name: "New Name", count: 5}

      # Check for errors after validation
      changeset.errors
      # => [] or [%ValidationError{...}]

      # Check validity
      changeset.valid?
      # => true or false

  """

  alias LiveSchema.ValidationError

  defstruct [
    :data,
    :module,
    changes: %{},
    errors: [],
    valid?: true
  ]

  @type t :: %__MODULE__{
          data: struct(),
          module: module(),
          changes: map(),
          errors: [ValidationError.t()],
          valid?: boolean()
        }

  @doc """
  Creates a new changeset from a state struct.
  """
  @spec new(struct()) :: t()
  def new(%{__struct__: module} = data) do
    %__MODULE__{
      data: data,
      module: module,
      changes: %{},
      errors: [],
      valid?: true
    }
  end

  @doc """
  Puts a change into the changeset.

  The change is not validated until `validate/1` is called.
  """
  @spec put(t(), atom(), any()) :: t()
  def put(%__MODULE__{} = changeset, field, value) do
    %{changeset | changes: Map.put(changeset.changes, field, value)}
  end

  @doc """
  Puts multiple changes into the changeset.
  """
  @spec put_changes(t(), map() | keyword()) :: t()
  def put_changes(%__MODULE__{} = changeset, changes) when is_map(changes) do
    %{changeset | changes: Map.merge(changeset.changes, changes)}
  end

  def put_changes(%__MODULE__{} = changeset, changes) when is_list(changes) do
    put_changes(changeset, Map.new(changes))
  end

  @doc """
  Validates all changes in the changeset.

  Runs type validation and custom validators for each changed field.
  """
  @spec validate(t()) :: t()
  def validate(%__MODULE__{} = changeset) do
    errors =
      changeset.changes
      |> Enum.flat_map(fn {field, value} ->
        case get_field_info(changeset.module, field) do
          nil ->
            []

          field_info ->
            case LiveSchema.Validation.validate_field(field, value, field_info) do
              :ok -> []
              {:error, error} -> [error]
            end
        end
      end)

    %{changeset | errors: errors, valid?: Enum.empty?(errors)}
  end

  @doc """
  Adds a custom validation to the changeset.
  """
  @spec validate_change(t(), atom(), (any() -> :ok | {:error, String.t()})) :: t()
  def validate_change(%__MODULE__{} = changeset, field, validator) do
    case Map.get(changeset.changes, field) do
      nil ->
        changeset

      value ->
        case validator.(value) do
          :ok ->
            changeset

          true ->
            changeset

          false ->
            add_error(changeset, field, "validation failed")

          {:error, message} ->
            add_error(changeset, field, message)
        end
    end
  end

  @doc """
  Adds an error to the changeset.
  """
  @spec add_error(t(), atom(), String.t()) :: t()
  def add_error(%__MODULE__{} = changeset, field, message) do
    error = %ValidationError{
      field: field,
      value: Map.get(changeset.changes, field),
      errors: [{:custom, message}],
      path: []
    }

    %{changeset | errors: [error | changeset.errors], valid?: false}
  end

  @doc """
  Applies the changes to the data if valid.

  Returns `{:ok, state}` if valid, `{:error, changeset}` if invalid.
  """
  @spec apply(t()) :: {:ok, struct()} | {:error, t()}
  def apply(%__MODULE__{valid?: true} = changeset) do
    new_data = struct(changeset.data, changeset.changes)
    {:ok, new_data}
  end

  def apply(%__MODULE__{valid?: false} = changeset) do
    {:error, changeset}
  end

  @doc """
  Applies the changes, raising on error.
  """
  @spec apply!(t()) :: struct()
  def apply!(%__MODULE__{} = changeset) do
    case __MODULE__.apply(changeset) do
      {:ok, data} ->
        data

      {:error, changeset} ->
        messages =
          changeset.errors
          |> Enum.map(&Exception.message/1)
          |> Enum.join("; ")

        raise ArgumentError, "Changeset validation failed: #{messages}"
    end
  end

  @doc """
  Returns the current value for a field (change or original).
  """
  @spec get_field(t(), atom(), any()) :: any()
  def get_field(%__MODULE__{} = changeset, field, default \\ nil) do
    case Map.fetch(changeset.changes, field) do
      {:ok, value} -> value
      :error -> Map.get(changeset.data, field, default)
    end
  end

  @doc """
  Returns the change for a field, or nil if unchanged.
  """
  @spec get_change(t(), atom(), any()) :: any()
  def get_change(%__MODULE__{} = changeset, field, default \\ nil) do
    Map.get(changeset.changes, field, default)
  end

  @doc """
  Returns true if the field has been changed.
  """
  @spec changed?(t(), atom()) :: boolean()
  def changed?(%__MODULE__{} = changeset, field) do
    Map.has_key?(changeset.changes, field)
  end

  @doc """
  Returns all field names that have changes.
  """
  @spec changed_fields(t()) :: [atom()]
  def changed_fields(%__MODULE__{} = changeset) do
    Map.keys(changeset.changes)
  end

  # Get field info from the schema module
  defp get_field_info(module, field) do
    if function_exported?(module, :__live_schema__, 1) do
      module.__live_schema__({:field, field})
    else
      nil
    end
  end
end
