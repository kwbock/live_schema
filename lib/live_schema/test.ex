defmodule LiveSchema.Test do
  @moduledoc """
  Testing utilities for LiveSchema.

  Provides helpers for testing state modules in isolation, generating
  test data, and making assertions about state transitions.

  ## Usage

      defmodule MyApp.StateTest do
        use ExUnit.Case
        use LiveSchema.Test

        alias MyApp.PostsState

        describe "select_post reducer" do
          test "selects a post by id" do
            state = PostsState.new!(posts: [%Post{id: 1}, %Post{id: 2}])

            new_state = PostsState.apply(state, {:select_post, 1})

            assert new_state.selected.id == 1
          end
        end
      end

  ## Assertions

  - `assert_valid_state/1` - Asserts state passes all validations
  - `assert_reducer_result/3` - Asserts reducer produces expected state
  - `refute_reduces/2` - Asserts action raises ActionError
  - `assert_changed/3` - Asserts specific fields changed

  ## Generators

  For property-based testing with StreamData:

      property "increment always increases count" do
        check all initial <- integer(0..100),
                  amount <- positive_integer() do
          state = CounterState.new!(count: initial)
          new_state = CounterState.apply(state, {:increment, amount})
          assert new_state.count == initial + amount
        end
      end

  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import LiveSchema.Test
      import LiveSchema.Diff, only: [assert_changed: 3]
    end
  end

  @doc """
  Asserts that a state struct passes all validations.

  ## Examples

      state = MyState.new!(name: "Test")
      assert_valid_state(state)

  """
  defmacro assert_valid_state(state) do
    quote do
      state = unquote(state)
      module = state.__struct__

      if function_exported?(module, :__live_schema__, 1) do
        fields = module.__live_schema__(:fields)

        Enum.each(fields, fn field ->
          field_info = module.__live_schema__({:field, field})
          value = Map.get(state, field)

          case LiveSchema.Validation.validate_field(field, value, field_info) do
            :ok ->
              :ok

            {:error, error} ->
              flunk("Validation failed for #{inspect(field)}: #{Exception.message(error)}")
          end
        end)
      end

      state
    end
  end

  @doc """
  Asserts that applying an action produces the expected result.

  Can compare against a full state or just specific fields.

  ## Examples

      # Full state comparison
      assert_reducer_result(state, {:increment}, %{count: 1})

      # Function-based assertion
      assert_reducer_result(state, {:increment}, fn new_state ->
        assert new_state.count > state.count
      end)

  """
  defmacro assert_reducer_result(state, action, expected) do
    quote do
      state = unquote(state)
      action = unquote(action)
      expected = unquote(expected)
      module = state.__struct__

      new_state = module.apply(state, action)

      case expected do
        %{__struct__: _} ->
          assert new_state == expected

        expected when is_map(expected) ->
          Enum.each(expected, fn {field, expected_value} ->
            actual_value = Map.get(new_state, field)

            assert actual_value == expected_value,
                   "Expected #{inspect(field)} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
          end)

        expected when is_function(expected, 1) ->
          expected.(new_state)
      end

      new_state
    end
  end

  @doc """
  Asserts that an action raises an ActionError.

  Use this to test that invalid actions are properly rejected.

  ## Examples

      refute_reduces(state, {:invalid_action})
      refute_reduces(state, {:increment, -1})  # If guarded to require positive

  """
  defmacro refute_reduces(state, action) do
    quote do
      state = unquote(state)
      action = unquote(action)
      module = state.__struct__

      assert_raise LiveSchema.ActionError, fn ->
        module.apply(state, action)
      end
    end
  end

  @doc """
  Asserts that exactly the specified fields changed.

  ## Examples

      assert_fields_changed(old_state, new_state, [:count, :updated_at])

  """
  def assert_fields_changed(old_state, new_state, expected_fields) do
    LiveSchema.Diff.assert_changed(old_state, new_state, expected_fields)
  end

  @doc """
  Builds a state struct with the given attributes.

  A simple factory function for tests.

  ## Examples

      state = build(MyState, count: 5, name: "Test")

  """
  def build(module, attrs \\ []) do
    module.new!(attrs)
  end

  @doc """
  Creates a StreamData generator for a LiveSchema module.

  Generates random valid states for property-based testing.

  ## Examples

      property "count is always non-negative" do
        check all state <- schema_generator(CounterState) do
          assert state.count >= 0
        end
      end

  """
  if Code.ensure_loaded?(StreamData) do
    @spec schema_generator(module()) :: StreamData.t(struct())
    def schema_generator(module) do
      if function_exported?(module, :__live_schema__, 1) do
        fields = module.__live_schema__(:fields)

        field_generators =
          Enum.map(fields, fn field ->
            field_info = module.__live_schema__({:field, field})
            {field, type_generator(field_info.type)}
          end)

        StreamData.fixed_map(field_generators)
        |> StreamData.map(fn attrs ->
          struct(module, attrs)
        end)
      else
        raise ArgumentError, "#{inspect(module)} is not a LiveSchema module"
      end
    end

    defp type_generator(:string), do: StreamData.string(:alphanumeric)
    defp type_generator(:integer), do: StreamData.integer()
    defp type_generator(:float), do: StreamData.float()
    defp type_generator(:boolean), do: StreamData.boolean()
    defp type_generator(:atom), do: StreamData.atom(:alphanumeric)
    defp type_generator(:any), do: StreamData.term()
    defp type_generator(:map), do: StreamData.map_of(StreamData.atom(:alphanumeric), StreamData.term())
    defp type_generator(:list), do: StreamData.list_of(StreamData.term())

    defp type_generator({:list, inner}) do
      StreamData.list_of(type_generator(inner))
    end

    defp type_generator({:nullable, inner}) do
      StreamData.one_of([StreamData.constant(nil), type_generator(inner)])
    end

    defp type_generator({:enum, values}) do
      StreamData.member_of(values)
    end

    defp type_generator({:struct, module}) do
      if function_exported?(module, :__live_schema__, 1) do
        schema_generator(module)
      else
        StreamData.constant(struct(module))
      end
    end

    defp type_generator(_), do: StreamData.term()
  end

  @doc """
  Mocks an async reducer for testing.

  ## Examples

      test "load_posts fetches and sets posts" do
        mock_async :load_posts, fn _filter ->
          [%Post{id: 1, title: "Test"}]
        end

        state = State.new()
        {:async, work_fn} = State.apply(state, {:load_posts, %{}})
        new_state = work_fn.()

        assert length(new_state.posts) == 1
      end

  """
  defmacro mock_async(action_name, mock_fn) do
    quote do
      # Store the mock in the process dictionary for the test
      Process.put({:live_schema_mock, unquote(action_name)}, unquote(mock_fn))
    end
  end

  @doc """
  Gets a stored mock function.

  Used internally by the testing framework.
  """
  def get_mock(action_name) do
    Process.get({:live_schema_mock, action_name})
  end

  @doc """
  Clears all mocks.
  """
  def clear_mocks do
    Process.get_keys()
    |> Enum.filter(fn
      {:live_schema_mock, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)
  end
end
