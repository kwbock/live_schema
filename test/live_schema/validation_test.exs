defmodule LiveSchema.ValidationTest do
  use ExUnit.Case, async: true

  alias LiveSchema.Validation
  alias LiveSchema.ValidationError

  describe "run_validator/2 - format" do
    test "passes when string matches regex" do
      assert :ok = Validation.run_validator({:format, ~r/@/}, "test@example.com")
      assert :ok = Validation.run_validator({:format, ~r/^\d{3}-\d{4}$/}, "123-4567")
    end

    test "fails when string does not match regex" do
      assert {:error, {:format, msg}} = Validation.run_validator({:format, ~r/@/}, "invalid")
      assert msg =~ "must match pattern"
    end

    test "fails with non-string value" do
      assert {:error, {:format, msg}} = Validation.run_validator({:format, ~r/@/}, 123)
      assert msg =~ "format validation requires a string"

      assert {:error, {:format, _}} = Validation.run_validator({:format, ~r/@/}, nil)
      assert {:error, {:format, _}} = Validation.run_validator({:format, ~r/@/}, [:list])
    end
  end

  describe "run_validator/2 - length" do
    test "passes when string length meets min" do
      assert :ok = Validation.run_validator({:length, [min: 3]}, "abc")
      assert :ok = Validation.run_validator({:length, [min: 3]}, "abcd")
    end

    test "fails when string length is below min" do
      assert {:error, {:length, msg}} = Validation.run_validator({:length, [min: 5]}, "abc")
      assert msg =~ "must be at least 5"
    end

    test "passes when string length meets max" do
      assert :ok = Validation.run_validator({:length, [max: 5]}, "abc")
      assert :ok = Validation.run_validator({:length, [max: 5]}, "abcde")
    end

    test "fails when string length exceeds max" do
      assert {:error, {:length, msg}} = Validation.run_validator({:length, [max: 3]}, "abcde")
      assert msg =~ "must be at most 3"
    end

    test "passes when string length is exactly :is value" do
      assert :ok = Validation.run_validator({:length, [is: 5]}, "abcde")
    end

    test "fails when string length is not exactly :is value" do
      assert {:error, {:length, msg}} = Validation.run_validator({:length, [is: 5]}, "abc")
      assert msg =~ "must be exactly 5"

      assert {:error, {:length, _}} = Validation.run_validator({:length, [is: 5]}, "abcdefgh")
    end

    test "works with min and max combined" do
      assert :ok = Validation.run_validator({:length, [min: 3, max: 5]}, "abc")
      assert :ok = Validation.run_validator({:length, [min: 3, max: 5]}, "abcde")
      assert {:error, {:length, _}} = Validation.run_validator({:length, [min: 3, max: 5]}, "ab")
      assert {:error, {:length, _}} = Validation.run_validator({:length, [min: 3, max: 5]}, "abcdef")
    end

    test "works with lists" do
      assert :ok = Validation.run_validator({:length, [min: 2]}, [1, 2, 3])
      assert :ok = Validation.run_validator({:length, [max: 5]}, [1, 2])
      assert :ok = Validation.run_validator({:length, [is: 3]}, [1, 2, 3])

      assert {:error, {:length, _}} = Validation.run_validator({:length, [min: 5]}, [1, 2])
      assert {:error, {:length, _}} = Validation.run_validator({:length, [max: 2]}, [1, 2, 3, 4])
      assert {:error, {:length, _}} = Validation.run_validator({:length, [is: 3]}, [1, 2])
    end

    test "fails with non-string/non-list value" do
      assert {:error, {:length, msg}} = Validation.run_validator({:length, [min: 1]}, 123)
      assert msg =~ "length validation requires string or list"

      assert {:error, {:length, _}} = Validation.run_validator({:length, [min: 1]}, %{})
    end
  end

  describe "run_validator/2 - inclusion" do
    test "passes when value is in list" do
      assert :ok = Validation.run_validator({:inclusion, [:a, :b, :c]}, :a)
      assert :ok = Validation.run_validator({:inclusion, [1, 2, 3]}, 2)
      assert :ok = Validation.run_validator({:inclusion, ["x", "y"]}, "x")
    end

    test "fails when value is not in list" do
      assert {:error, {:inclusion, msg}} = Validation.run_validator({:inclusion, [:a, :b]}, :c)
      assert msg =~ "must be one of"
    end
  end

  describe "run_validator/2 - exclusion" do
    test "passes when value is not in list" do
      assert :ok = Validation.run_validator({:exclusion, [:blocked, :banned]}, :allowed)
      assert :ok = Validation.run_validator({:exclusion, [1, 2]}, 3)
    end

    test "fails when value is in list" do
      assert {:error, {:exclusion, msg}} = Validation.run_validator({:exclusion, [:blocked]}, :blocked)
      assert msg =~ "must not be one of"
    end
  end

  describe "run_validator/2 - custom" do
    test "passes when function returns true" do
      validator = fn x -> x > 0 end
      assert :ok = Validation.run_validator({:custom, validator}, 5)
    end

    test "passes when function returns :ok" do
      validator = fn _ -> :ok end
      assert :ok = Validation.run_validator({:custom, validator}, "any")
    end

    test "fails when function returns false" do
      validator = fn x -> x > 10 end
      assert {:error, {:custom, msg}} = Validation.run_validator({:custom, validator}, 5)
      assert msg == "validation failed"
    end

    test "fails when function returns {:error, message}" do
      validator = fn x ->
        if rem(x, 2) == 0, do: :ok, else: {:error, "must be even"}
      end

      assert :ok = Validation.run_validator({:custom, validator}, 4)
      assert {:error, {:custom, "must be even"}} = Validation.run_validator({:custom, validator}, 5)
    end
  end

  describe "run_validator/2 - number" do
    test "passes when value is greater_than threshold" do
      assert :ok = Validation.run_validator({:number, [greater_than: 0]}, 1)
      assert :ok = Validation.run_validator({:number, [greater_than: 0]}, 0.1)
    end

    test "fails when value is not greater_than threshold" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [greater_than: 0]}, 0)
      assert msg =~ "must be greater than 0"

      assert {:error, {:number, _}} = Validation.run_validator({:number, [greater_than: 5]}, 3)
    end

    test "passes when value is greater_than_or_equal_to threshold" do
      assert :ok = Validation.run_validator({:number, [greater_than_or_equal_to: 0]}, 0)
      assert :ok = Validation.run_validator({:number, [greater_than_or_equal_to: 5]}, 5)
      assert :ok = Validation.run_validator({:number, [greater_than_or_equal_to: 5]}, 10)
    end

    test "fails when value is less than greater_than_or_equal_to threshold" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [greater_than_or_equal_to: 5]}, 4)
      assert msg =~ "must be greater than or equal to 5"
    end

    test "passes when value is less_than threshold" do
      assert :ok = Validation.run_validator({:number, [less_than: 10]}, 9)
      assert :ok = Validation.run_validator({:number, [less_than: 0]}, -1)
    end

    test "fails when value is not less_than threshold" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [less_than: 10]}, 10)
      assert msg =~ "must be less than 10"

      assert {:error, {:number, _}} = Validation.run_validator({:number, [less_than: 5]}, 7)
    end

    test "passes when value is less_than_or_equal_to threshold" do
      assert :ok = Validation.run_validator({:number, [less_than_or_equal_to: 10]}, 10)
      assert :ok = Validation.run_validator({:number, [less_than_or_equal_to: 10]}, 5)
    end

    test "fails when value exceeds less_than_or_equal_to threshold" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [less_than_or_equal_to: 10]}, 11)
      assert msg =~ "must be less than or equal to 10"
    end

    test "passes when value equals equal_to value" do
      assert :ok = Validation.run_validator({:number, [equal_to: 42]}, 42)
      assert :ok = Validation.run_validator({:number, [equal_to: 0.5]}, 0.5)
    end

    test "fails when value does not equal equal_to value" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [equal_to: 42]}, 41)
      assert msg =~ "must be equal to 42"
    end

    test "works with multiple number constraints" do
      opts = [greater_than_or_equal_to: 0, less_than: 100]
      assert :ok = Validation.run_validator({:number, opts}, 50)
      assert {:error, {:number, _}} = Validation.run_validator({:number, opts}, -1)
      assert {:error, {:number, _}} = Validation.run_validator({:number, opts}, 100)
    end

    test "fails with non-number value" do
      assert {:error, {:number, msg}} = Validation.run_validator({:number, [greater_than: 0]}, "5")
      assert msg =~ "number validation requires a number"

      assert {:error, {:number, _}} = Validation.run_validator({:number, [less_than: 10]}, nil)
    end
  end

  describe "run_validator/2 - unknown validator" do
    test "returns error for unknown validator type" do
      assert {:error, {:unknown_type, msg}} = Validation.run_validator({:unknown_type, []}, "value")
      assert msg =~ "unknown validator"
    end
  end

  describe "validate_field/3" do
    test "passes with valid type and no validators" do
      field_info = %{type: :string}
      assert :ok = Validation.validate_field(:name, "test", field_info)
    end

    test "fails with invalid type" do
      field_info = %{type: :string}
      assert {:error, %ValidationError{field: :name, errors: errors}} =
               Validation.validate_field(:name, 123, field_info)

      assert Enum.any?(errors, fn {type, _} -> type == :type end)
    end

    test "passes with valid type and passing validators" do
      field_info = %{
        type: :string,
        validate: [format: ~r/@/, length: [min: 5]]
      }

      assert :ok = Validation.validate_field(:email, "test@example.com", field_info)
    end

    test "fails when validator fails even if type is valid" do
      field_info = %{
        type: :string,
        validate: [format: ~r/@/]
      }

      assert {:error, %ValidationError{field: :email, errors: errors}} =
               Validation.validate_field(:email, "invalid", field_info)

      assert Enum.any?(errors, fn {type, _} -> type == :format end)
    end

    test "collects multiple validation errors" do
      field_info = %{
        type: :string,
        validate: [format: ~r/^\d+$/, length: [min: 10]]
      }

      assert {:error, %ValidationError{errors: errors}} =
               Validation.validate_field(:code, "abc", field_info)

      # Both format and length should fail
      assert length(errors) == 2
      error_types = Enum.map(errors, fn {type, _} -> type end)
      assert :format in error_types
      assert :length in error_types
    end

    test "passes when nullable field is nil" do
      field_info = %{type: :string, nullable: true}
      assert :ok = Validation.validate_field(:optional, nil, field_info)
    end

    test "still validates non-nil value on nullable field" do
      field_info = %{type: :string, nullable: true, validate: [length: [min: 3]]}

      assert :ok = Validation.validate_field(:optional, "abc", field_info)
      assert {:error, %ValidationError{}} = Validation.validate_field(:optional, "ab", field_info)
    end

    test "fails when non-nullable field is nil" do
      field_info = %{type: :string, nullable: false}
      assert {:error, %ValidationError{}} = Validation.validate_field(:required, nil, field_info)
    end

    test "works with function validator directly" do
      field_info = %{
        type: :integer,
        validate: fn x -> x > 0 end
      }

      assert :ok = Validation.validate_field(:count, 5, field_info)
      assert {:error, %ValidationError{errors: [{:custom, _}]}} =
               Validation.validate_field(:count, -1, field_info)
    end

    test "function validator returning :ok passes" do
      field_info = %{type: :integer, validate: fn _ -> :ok end}
      assert :ok = Validation.validate_field(:value, 42, field_info)
    end

    test "function validator returning {:error, msg} fails with message" do
      field_info = %{
        type: :integer,
        validate: fn x ->
          if x > 0, do: :ok, else: {:error, "must be positive"}
        end
      }

      assert {:error, %ValidationError{errors: [{:custom, "must be positive"}]}} =
               Validation.validate_field(:value, -5, field_info)
    end
  end

  describe "handle_error/3" do
    setup do
      # Store original config to restore after tests
      original = Application.get_env(:live_schema, :on_error)
      on_exit(fn -> Application.put_env(:live_schema, :on_error, original) end)
      :ok
    end

    test "raises TypeError when on_error is :raise" do
      Application.put_env(:live_schema, :on_error, :raise)

      error = %ValidationError{
        field: :name,
        value: 123,
        errors: [{:type, "expected string"}],
        path: []
      }

      assert_raise LiveSchema.TypeError, fn ->
        Validation.handle_error({:error, error}, TestModule, :name)
      end
    end

    test "logs warning when on_error is :log" do
      import ExUnit.CaptureLog

      Application.put_env(:live_schema, :on_error, :log)

      error = %ValidationError{
        field: :name,
        value: 123,
        errors: [{:type, "expected string"}],
        path: []
      }

      # Should return :ok and log a warning
      log = capture_log(fn ->
        assert :ok = Validation.handle_error({:error, error}, TestModule, :name)
      end)

      assert log =~ "LiveSchema validation error"
      assert log =~ "TestModule"
      assert log =~ ":name"
    end

    test "returns :ok silently when on_error is :ignore" do
      Application.put_env(:live_schema, :on_error, :ignore)

      error = %ValidationError{
        field: :name,
        value: 123,
        errors: [{:type, "expected string"}],
        path: []
      }

      assert :ok = Validation.handle_error({:error, error}, TestModule, :name)
    end

    test "defaults to :log when not configured" do
      import ExUnit.CaptureLog

      Application.delete_env(:live_schema, :on_error)

      error = %ValidationError{
        field: :name,
        value: 123,
        errors: [{:type, "expected string"}],
        path: []
      }

      # Should not raise, defaults to log
      log = capture_log(fn ->
        assert :ok = Validation.handle_error({:error, error}, TestModule, :name)
      end)

      assert log =~ "LiveSchema validation error"
    end
  end

  describe "validation_enabled?/0" do
    setup do
      original = Application.get_env(:live_schema, :validate_at)
      on_exit(fn -> Application.put_env(:live_schema, :validate_at, original) end)
      :ok
    end

    test "returns true when validate_at is :runtime" do
      Application.put_env(:live_schema, :validate_at, :runtime)
      assert Validation.validation_enabled?() == true
    end

    test "returns false when validate_at is :none" do
      Application.put_env(:live_schema, :validate_at, :none)
      assert Validation.validation_enabled?() == false
    end

    test "defaults to false when not configured" do
      Application.delete_env(:live_schema, :validate_at)
      assert Validation.validation_enabled?() == false
    end
  end
end
