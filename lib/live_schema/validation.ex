defmodule LiveSchema.Validation do
  @moduledoc """
  Runtime validation for LiveSchema fields.

  Validation can be enabled globally via configuration or per-field via options.

  ## Configuration

      # config/dev.exs
      config :live_schema,
        validate_at: :runtime,  # :runtime | :none
        on_error: :log          # :log | :raise | :ignore

  ## Per-field Validation

      schema do
        field :email, :string, validate: [
          format: ~r/@/,
          length: [min: 5, max: 255]
        ]

        field :status, {:enum, [:active, :inactive]}, validate: &custom_check/1
      end

  ## Built-in Validators

  - `format: ~r/pattern/` - String must match regex
  - `length: [min: n, max: m]` - String/list length bounds
  - `inclusion: [values]` - Value must be in list
  - `exclusion: [values]` - Value must not be in list
  - `custom: &function/1` - Custom validation function

  """

  alias LiveSchema.{TypeError, ValidationError}

  @doc """
  Validates a field value against type and custom validators.

  Returns `:ok` or `{:error, ValidationError.t()}`.
  """
  @spec validate_field(atom(), any(), map()) :: :ok | {:error, ValidationError.t()}
  def validate_field(name, value, field_info) do
    errors = []

    # Type validation
    errors =
      case LiveSchema.Types.validate_type(value, field_info.type) do
        :ok -> errors
        {:error, reason} -> [{:type, reason} | errors]
      end

    # Custom validators
    errors =
      case field_info[:validate] do
        nil ->
          errors

        validators when is_list(validators) ->
          Enum.reduce(validators, errors, fn validator, acc ->
            case run_validator(validator, value) do
              :ok -> acc
              {:error, {type, msg}} -> [{type, msg} | acc]
            end
          end)

        validator when is_function(validator, 1) ->
          case validator.(value) do
            true -> errors
            :ok -> errors
            false -> [{:custom, "validation failed"} | errors]
            {:error, msg} -> [{:custom, msg} | errors]
          end
      end

    case errors do
      [] ->
        :ok

      _ ->
        {:error,
         %ValidationError{
           field: name,
           value: value,
           errors: Enum.reverse(errors),
           path: []
         }}
    end
  end

  @doc """
  Runs a single validator against a value.
  """
  @spec run_validator({atom(), any()}, any()) :: :ok | {:error, {atom(), String.t()}}
  def run_validator({:format, regex}, value) when is_binary(value) do
    if Regex.match?(regex, value) do
      :ok
    else
      {:error, {:format, "must match pattern #{inspect(regex)}"}}
    end
  end

  def run_validator({:format, _}, value) do
    {:error, {:format, "format validation requires a string, got #{inspect(value)}"}}
  end

  def run_validator({:length, opts}, value) when is_binary(value) do
    len = String.length(value)
    validate_length(len, opts)
  end

  def run_validator({:length, opts}, value) when is_list(value) do
    len = length(value)
    validate_length(len, opts)
  end

  def run_validator({:length, _opts}, value) do
    {:error, {:length, "length validation requires string or list, got #{inspect(value)}"}}
  end

  def run_validator({:inclusion, values}, value) do
    if value in values do
      :ok
    else
      {:error, {:inclusion, "must be one of #{inspect(values)}"}}
    end
  end

  def run_validator({:exclusion, values}, value) do
    if value in values do
      {:error, {:exclusion, "must not be one of #{inspect(values)}"}}
    else
      :ok
    end
  end

  def run_validator({:custom, func}, value) when is_function(func, 1) do
    case func.(value) do
      true -> :ok
      :ok -> :ok
      false -> {:error, {:custom, "validation failed"}}
      {:error, msg} -> {:error, {:custom, msg}}
    end
  end

  def run_validator({:number, opts}, value) when is_number(value) do
    validate_number(value, opts)
  end

  def run_validator({:number, _opts}, value) do
    {:error, {:number, "number validation requires a number, got #{inspect(value)}"}}
  end

  def run_validator({type, _opts}, _value) do
    {:error, {type, "unknown validator: #{type}"}}
  end

  defp validate_length(len, opts) do
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)
    is = Keyword.get(opts, :is)

    cond do
      is != nil and len != is ->
        {:error, {:length, "must be exactly #{is} characters/items"}}

      min != nil and len < min ->
        {:error, {:length, "must be at least #{min} characters/items"}}

      max != nil and len > max ->
        {:error, {:length, "must be at most #{max} characters/items"}}

      true ->
        :ok
    end
  end

  defp validate_number(value, opts) do
    greater_than = Keyword.get(opts, :greater_than)
    greater_than_or_equal = Keyword.get(opts, :greater_than_or_equal_to)
    less_than = Keyword.get(opts, :less_than)
    less_than_or_equal = Keyword.get(opts, :less_than_or_equal_to)
    equal_to = Keyword.get(opts, :equal_to)

    cond do
      equal_to != nil and value != equal_to ->
        {:error, {:number, "must be equal to #{equal_to}"}}

      greater_than != nil and value <= greater_than ->
        {:error, {:number, "must be greater than #{greater_than}"}}

      greater_than_or_equal != nil and value < greater_than_or_equal ->
        {:error, {:number, "must be greater than or equal to #{greater_than_or_equal}"}}

      less_than != nil and value >= less_than ->
        {:error, {:number, "must be less than #{less_than}"}}

      less_than_or_equal != nil and value > less_than_or_equal ->
        {:error, {:number, "must be less than or equal to #{less_than_or_equal}"}}

      true ->
        :ok
    end
  end

  @doc """
  Handles a validation error based on configuration.
  """
  @spec handle_error({:error, ValidationError.t()}, module(), atom()) :: :ok
  def handle_error({:error, error}, module, field) do
    on_error = Application.get_env(:live_schema, :on_error, :log)

    case on_error do
      :raise ->
        raise TypeError,
          field: field,
          expected: format_expected(error),
          got: inspect(error.value),
          path: error.path

      :log ->
        require Logger
        Logger.warning("LiveSchema validation error in #{inspect(module)}: #{Exception.message(error)}")
        :ok

      :ignore ->
        :ok
    end
  end

  defp format_expected(%ValidationError{errors: errors}) do
    errors
    |> Enum.map(fn {type, msg} -> "#{type}: #{msg}" end)
    |> Enum.join(", ")
  end

  @doc """
  Returns whether validation is enabled.
  """
  @spec validation_enabled?() :: boolean()
  def validation_enabled? do
    Application.get_env(:live_schema, :validate_at, :none) == :runtime
  end
end
