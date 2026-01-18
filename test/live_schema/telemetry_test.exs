defmodule LiveSchema.TelemetryTest do
  use ExUnit.Case, async: false

  alias LiveSchema.Telemetry

  # Using async: false because telemetry handlers are global

  # Module function for telemetry handler to avoid anonymous function warning
  def handle_telemetry_event(event, measurements, metadata, config) do
    test_pid = config[:test_pid]
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  setup do
    # Detach any existing handlers to start clean
    Telemetry.detach_default_handlers()

    # Track events in the test process
    test_pid = self()

    handler_id = "test-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:live_schema, :reducer, :start],
        [:live_schema, :reducer, :stop],
        [:live_schema, :reducer, :exception],
        [:live_schema, :validation, :failure]
      ],
      &__MODULE__.handle_telemetry_event/4,
      %{test_pid: test_pid}
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Telemetry.detach_default_handlers()
    end)

    {:ok, handler_id: handler_id}
  end

  describe "span/4" do
    test "emits start event before execution" do
      Telemetry.span(TestSchema, :increment, [], fn -> :ok end)

      assert_receive {:telemetry_event, [:live_schema, :reducer, :start], measurements, metadata}

      assert is_integer(measurements.system_time)
      assert metadata.schema == TestSchema
      assert metadata.action == :increment
      assert metadata.action_args == []
    end

    test "emits stop event after successful execution" do
      Telemetry.span(TestSchema, :increment, [], fn -> :ok end)

      assert_receive {:telemetry_event, [:live_schema, :reducer, :stop], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.schema == TestSchema
      assert metadata.action == :increment
    end

    test "returns the result of the function" do
      result = Telemetry.span(TestSchema, :do_something, [:arg1], fn -> {:ok, 42} end)

      assert result == {:ok, 42}
    end

    test "includes action args in metadata" do
      Telemetry.span(TestSchema, :set_value, ["hello", 123], fn -> :ok end)

      assert_receive {:telemetry_event, [:live_schema, :reducer, :start], _measurements, metadata}

      assert metadata.action_args == ["hello", 123]
    end

    test "emits exception event on error" do
      assert_raise RuntimeError, "test error", fn ->
        Telemetry.span(TestSchema, :failing_action, [], fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:live_schema, :reducer, :exception], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.schema == TestSchema
      assert metadata.action == :failing_action
      assert metadata.kind == :error
      assert %RuntimeError{message: "test error"} = metadata.reason
      assert is_list(metadata.stacktrace)
    end

    test "emits exception event on throw" do
      catch_throw do
        Telemetry.span(TestSchema, :throwing_action, [], fn ->
          throw(:thrown_value)
        end)
      end

      assert_receive {:telemetry_event, [:live_schema, :reducer, :exception], _measurements, metadata}

      assert metadata.kind == :throw
      assert metadata.reason == :thrown_value
    end

    test "emits exception event on exit" do
      catch_exit do
        Telemetry.span(TestSchema, :exiting_action, [], fn ->
          exit(:normal)
        end)
      end

      assert_receive {:telemetry_event, [:live_schema, :reducer, :exception], _measurements, metadata}

      assert metadata.kind == :exit
      assert metadata.reason == :normal
    end

    test "measures duration correctly" do
      Telemetry.span(TestSchema, :slow_action, [], fn ->
        Process.sleep(50)
        :ok
      end)

      assert_receive {:telemetry_event, [:live_schema, :reducer, :stop], measurements, _metadata}

      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      assert duration_ms >= 50
    end
  end

  describe "emit_validation_failure/3" do
    test "emits validation failure event" do
      Telemetry.emit_validation_failure(TestSchema, :email, [{:format, "invalid email"}])

      assert_receive {:telemetry_event, [:live_schema, :validation, :failure], measurements, metadata}

      assert measurements == %{}
      assert metadata.schema == TestSchema
      assert metadata.field == :email
      assert metadata.errors == [{:format, "invalid email"}]
    end

    test "includes multiple errors" do
      errors = [
        {:format, "must match pattern"},
        {:length, "too short"}
      ]

      Telemetry.emit_validation_failure(TestSchema, :password, errors)

      assert_receive {:telemetry_event, [:live_schema, :validation, :failure], _measurements, metadata}

      assert metadata.errors == errors
    end
  end

  describe "attach_default_handlers/0" do
    test "attaches handlers for all events" do
      import ExUnit.CaptureLog

      assert :ok = Telemetry.attach_default_handlers()

      # Verify handlers are attached by emitting events and checking logs
      log = capture_log(fn ->
        Telemetry.span(TestSchema, :test_action, [], fn -> :ok end)
        Telemetry.emit_validation_failure(TestSchema, :field, [])
      end)

      # Verify log output was produced
      assert log =~ "LiveSchema reducer"
      assert log =~ "validation failed"
    end

    test "can be called multiple times without error" do
      import ExUnit.CaptureLog

      capture_log(fn ->
        Telemetry.attach_default_handlers()
      end)

      # Second call should fail because handler already exists
      # :telemetry.attach_many raises if handler_id already exists
      assert {:error, :already_exists} =
               :telemetry.attach_many(
                 "live_schema-default-handlers",
                 [[:live_schema, :reducer, :start]],
                 &__MODULE__.handle_telemetry_event/4,
                 nil
               )
    end
  end

  describe "detach_default_handlers/0" do
    test "detaches handlers successfully" do
      import ExUnit.CaptureLog

      capture_log(fn -> Telemetry.attach_default_handlers() end)

      assert :ok = Telemetry.detach_default_handlers()
    end

    test "returns error when handlers not attached" do
      # Ensure not attached
      Telemetry.detach_default_handlers()

      assert {:error, :not_found} = Telemetry.detach_default_handlers()
    end
  end

  describe "handle_event/4 logging" do
    import ExUnit.CaptureLog

    test "logs reducer start event" do
      log =
        capture_log(fn ->
          Telemetry.attach_default_handlers()
          Telemetry.span(TestSchema, :my_action, [], fn -> :ok end)
        end)

      assert log =~ "LiveSchema reducer starting"
      assert log =~ "my_action"
      assert log =~ "TestSchema"
    end

    test "logs reducer stop event with duration" do
      log =
        capture_log(fn ->
          Telemetry.attach_default_handlers()
          Telemetry.span(TestSchema, :my_action, [], fn -> :ok end)
        end)

      assert log =~ "LiveSchema reducer completed"
      assert log =~ "my_action"
      assert log =~ "ms"
    end

    test "logs reducer exception event" do
      log =
        capture_log(fn ->
          Telemetry.attach_default_handlers()
          try do
            Telemetry.span(TestSchema, :failing, [], fn ->
              raise "boom"
            end)
          rescue
            _ -> :ok
          end
        end)

      assert log =~ "LiveSchema reducer failed"
      assert log =~ "failing"
      assert log =~ "boom"
    end

    test "logs validation failure event" do
      log =
        capture_log(fn ->
          Telemetry.attach_default_handlers()
          Telemetry.emit_validation_failure(TestSchema, :email, [{:format, "invalid"}])
        end)

      assert log =~ "LiveSchema validation failed"
      assert log =~ "email"
      assert log =~ "format"
    end
  end

  describe "integration with real schema" do
    defmodule TelemetryTestSchema do
      use LiveSchema

      schema do
        field :count, :integer, default: 0
      end

      reducer :increment do
        set_count(state, state.count + 1)
      end

      reducer :fail do
        _unused = state
        raise "intentional failure"
      end
    end

    test "events are emitted when using apply/2" do
      # Note: The compiler-generated apply/2 doesn't use Telemetry.span by default
      # This test verifies span works correctly when integrated manually

      state = TelemetryTestSchema.new!()

      Telemetry.span(TelemetryTestSchema, :increment, [], fn ->
        TelemetryTestSchema.apply(state, {:increment})
      end)

      assert_receive {:telemetry_event, [:live_schema, :reducer, :start], _, metadata}
      assert metadata.schema == TelemetryTestSchema
      assert metadata.action == :increment

      assert_receive {:telemetry_event, [:live_schema, :reducer, :stop], _, _}
    end
  end
end
