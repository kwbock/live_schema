defmodule LiveSchema.Telemetry do
  @moduledoc """
  Telemetry integration for LiveSchema.

  LiveSchema emits telemetry events that can be used for observability,
  debugging, and performance monitoring.

  ## Events

  ### `[:live_schema, :reducer, :start]`

  Emitted before a reducer is executed.

  **Measurements:** `%{system_time: integer()}`

  **Metadata:**
  - `:schema` - The schema module
  - `:action` - The action name (atom)
  - `:action_args` - The action arguments

  ### `[:live_schema, :reducer, :stop]`

  Emitted after a reducer completes successfully.

  **Measurements:** `%{duration: integer()}`

  **Metadata:**
  - `:schema` - The schema module
  - `:action` - The action name
  - `:action_args` - The action arguments

  ### `[:live_schema, :reducer, :exception]`

  Emitted when a reducer raises an exception.

  **Measurements:** `%{duration: integer()}`

  **Metadata:**
  - `:schema` - The schema module
  - `:action` - The action name
  - `:kind` - The exception kind (:error, :exit, :throw)
  - `:reason` - The exception reason
  - `:stacktrace` - The stacktrace

  ### `[:live_schema, :validation, :failure]`

  Emitted when validation fails.

  **Measurements:** `%{}`

  **Metadata:**
  - `:schema` - The schema module
  - `:field` - The field that failed validation
  - `:errors` - List of validation errors

  ## Attaching Handlers

      # In your application.ex
      def start(_type, _args) do
        LiveSchema.Telemetry.attach_default_handlers()
        # ...
      end

  Or attach custom handlers:

      :telemetry.attach(
        "my-reducer-handler",
        [:live_schema, :reducer, :stop],
        &MyApp.Telemetry.handle_reducer/4,
        nil
      )

  """

  @doc """
  Attaches default telemetry handlers for logging.

  Call this in your application startup if you want automatic logging
  of LiveSchema events.
  """
  @spec attach_default_handlers() :: :ok
  def attach_default_handlers do
    events = [
      [:live_schema, :reducer, :start],
      [:live_schema, :reducer, :stop],
      [:live_schema, :reducer, :exception],
      [:live_schema, :validation, :failure]
    ]

    :telemetry.attach_many(
      "live_schema-default-handlers",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Detaches the default handlers.
  """
  @spec detach_default_handlers() :: :ok | {:error, :not_found}
  def detach_default_handlers do
    :telemetry.detach("live_schema-default-handlers")
  end

  @doc false
  def handle_event([:live_schema, :reducer, :start], _measurements, metadata, _config) do
    require Logger
    Logger.debug("LiveSchema reducer starting: #{inspect(metadata.action)} in #{inspect(metadata.schema)}")
  end

  def handle_event([:live_schema, :reducer, :stop], measurements, metadata, _config) do
    require Logger
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug(
      "LiveSchema reducer completed: #{inspect(metadata.action)} in #{inspect(metadata.schema)} (#{duration_ms}ms)"
    )
  end

  def handle_event([:live_schema, :reducer, :exception], measurements, metadata, _config) do
    require Logger
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error("""
    LiveSchema reducer failed: #{inspect(metadata.action)} in #{inspect(metadata.schema)}
    Kind: #{metadata.kind}
    Reason: #{inspect(metadata.reason)}
    Duration: #{duration_ms}ms
    """)
  end

  def handle_event([:live_schema, :validation, :failure], _measurements, metadata, _config) do
    require Logger

    Logger.warning(
      "LiveSchema validation failed for #{inspect(metadata.field)} in #{inspect(metadata.schema)}: #{inspect(metadata.errors)}"
    )
  end

  @doc """
  Wraps a reducer execution with telemetry events.

  Used internally by the generated apply/2 function.
  """
  @spec span(module(), atom(), list(), (-> any())) :: any()
  def span(schema, action, args, fun) do
    metadata = %{
      schema: schema,
      action: action,
      action_args: args
    }

    :telemetry.span(
      [:live_schema, :reducer],
      metadata,
      fn ->
        result = fun.()
        {result, metadata}
      end
    )
  end

  @doc """
  Emits a validation failure event.
  """
  @spec emit_validation_failure(module(), atom(), list()) :: :ok
  def emit_validation_failure(schema, field, errors) do
    :telemetry.execute(
      [:live_schema, :validation, :failure],
      %{},
      %{
        schema: schema,
        field: field,
        errors: errors
      }
    )
  end
end
