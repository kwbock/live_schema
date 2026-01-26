defmodule LiveSchema.MiddlewareTest do
  use ExUnit.Case, async: false

  # Using async: false because we use a named Agent to track hook calls

  setup do
    # Start an agent to track hook calls for each test
    {:ok, agent} = Agent.start_link(fn -> [] end, name: :hook_tracker)

    on_exit(fn ->
      try do
        if Process.whereis(:hook_tracker), do: Agent.stop(:hook_tracker)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, agent: agent}
  end

  defp get_calls do
    Agent.get(:hook_tracker, & &1)
  end

  # Schema with before_action hook
  defmodule BeforeHookSchema do
    use LiveSchema

    before_action(:on_before)

    schema do
      field :count, :integer, default: 0
    end

    action :increment do
      set_count(state, state.count + 1)
    end

    def on_before(state, action) do
      Agent.update(:hook_tracker, fn calls ->
        calls ++ [{:before, state.count, action}]
      end)
    end
  end

  # Schema with after_action hook
  defmodule AfterHookSchema do
    use LiveSchema

    after_action(:on_after)

    schema do
      field :count, :integer, default: 0
    end

    action :increment do
      set_count(state, state.count + 1)
    end

    def on_after(old_state, new_state, action) do
      Agent.update(:hook_tracker, fn calls ->
        calls ++ [{:after, old_state.count, new_state.count, action}]
      end)
    end
  end

  # Schema with both before and after hooks
  defmodule BothHooksSchema do
    use LiveSchema

    before_action(:on_before)
    after_action(:on_after)

    schema do
      field :value, :string, default: ""
    end

    action :set_value, [:new_value] do
      set_value(state, new_value)
    end

    def on_before(state, action) do
      Agent.update(:hook_tracker, fn calls ->
        calls ++ [{:before, state.value, action}]
      end)
    end

    def on_after(old_state, new_state, action) do
      Agent.update(:hook_tracker, fn calls ->
        calls ++ [{:after, old_state.value, new_state.value, action}]
      end)
    end
  end

  # Schema with multiple hooks of each type
  defmodule MultipleHooksSchema do
    use LiveSchema

    before_action(:before_first)
    before_action(:before_second)
    after_action(:after_first)
    after_action(:after_second)

    schema do
      field :count, :integer, default: 0
    end

    action :increment do
      set_count(state, state.count + 1)
    end

    def before_first(_state, _action) do
      Agent.update(:hook_tracker, fn calls -> calls ++ [:before_first] end)
    end

    def before_second(_state, _action) do
      Agent.update(:hook_tracker, fn calls -> calls ++ [:before_second] end)
    end

    def after_first(_old, _new, _action) do
      Agent.update(:hook_tracker, fn calls -> calls ++ [:after_first] end)
    end

    def after_second(_old, _new, _action) do
      Agent.update(:hook_tracker, fn calls -> calls ++ [:after_second] end)
    end
  end

  # Schema with no hooks for comparison
  defmodule NoHooksSchema do
    use LiveSchema

    schema do
      field :count, :integer, default: 0
    end

    action :increment do
      set_count(state, state.count + 1)
    end
  end

  describe "before_action/1" do
    test "hook is called before action executes" do
      state = BeforeHookSchema.new!()

      # Apply the action
      new_state = BeforeHookSchema.apply(state, {:increment})

      # Verify hook was called
      calls = get_calls()
      assert length(calls) == 1
      assert [{:before, 0, {:increment}}] = calls

      # Verify action still worked
      assert new_state.count == 1
    end

    test "hook receives current state and action" do
      state = BeforeHookSchema.new!(count: 5)

      BeforeHookSchema.apply(state, {:increment})

      calls = get_calls()
      [{:before, count, action}] = calls

      assert count == 5
      assert action == {:increment}
    end

    test "hook is called for each apply" do
      state = BeforeHookSchema.new!()

      state = BeforeHookSchema.apply(state, {:increment})
      state = BeforeHookSchema.apply(state, {:increment})
      _state = BeforeHookSchema.apply(state, {:increment})

      calls = get_calls()
      assert length(calls) == 3

      # Each call should have the state at that point
      assert [{:before, 0, _}, {:before, 1, _}, {:before, 2, _}] = calls
    end
  end

  describe "after_action/1" do
    test "hook is called after action executes" do
      state = AfterHookSchema.new!()

      new_state = AfterHookSchema.apply(state, {:increment})

      calls = get_calls()
      assert length(calls) == 1
      assert [{:after, 0, 1, {:increment}}] = calls

      assert new_state.count == 1
    end

    test "hook receives old state, new state, and action" do
      state = AfterHookSchema.new!(count: 10)

      AfterHookSchema.apply(state, {:increment})

      calls = get_calls()
      [{:after, old_count, new_count, action}] = calls

      assert old_count == 10
      assert new_count == 11
      assert action == {:increment}
    end

    test "hook is called for each apply" do
      state = AfterHookSchema.new!()

      state = AfterHookSchema.apply(state, {:increment})
      state = AfterHookSchema.apply(state, {:increment})
      _state = AfterHookSchema.apply(state, {:increment})

      calls = get_calls()
      assert length(calls) == 3

      # Verify state transitions in each call
      assert [
               {:after, 0, 1, _},
               {:after, 1, 2, _},
               {:after, 2, 3, _}
             ] = calls
    end
  end

  describe "before and after hooks together" do
    test "both hooks are called in correct order" do
      state = BothHooksSchema.new!()

      BothHooksSchema.apply(state, {:set_value, "hello"})

      calls = get_calls()
      assert length(calls) == 2

      # Before should be first, after should be second
      assert [{:before, "", {:set_value, "hello"}}, {:after, "", "hello", {:set_value, "hello"}}] =
               calls
    end

    test "before sees pre-change state, after sees both states" do
      state = BothHooksSchema.new!(value: "old")

      BothHooksSchema.apply(state, {:set_value, "new"})

      calls = get_calls()

      [{:before, before_value, _}, {:after, old_value, new_value, _}] = calls

      assert before_value == "old"
      assert old_value == "old"
      assert new_value == "new"
    end
  end

  describe "multiple hooks" do
    test "multiple before hooks execute in registration order" do
      state = MultipleHooksSchema.new!()

      MultipleHooksSchema.apply(state, {:increment})

      calls = get_calls()

      # Filter to just before hooks
      before_calls =
        Enum.filter(calls, fn
          :before_first -> true
          :before_second -> true
          _ -> false
        end)

      assert before_calls == [:before_first, :before_second]
    end

    test "multiple after hooks execute in registration order" do
      state = MultipleHooksSchema.new!()

      MultipleHooksSchema.apply(state, {:increment})

      calls = get_calls()

      # Filter to just after hooks
      after_calls =
        Enum.filter(calls, fn
          :after_first -> true
          :after_second -> true
          _ -> false
        end)

      assert after_calls == [:after_first, :after_second]
    end

    test "all hooks execute: before hooks, action, then after hooks" do
      state = MultipleHooksSchema.new!()

      MultipleHooksSchema.apply(state, {:increment})

      calls = get_calls()

      # Should be: before_first, before_second, after_first, after_second
      assert calls == [:before_first, :before_second, :after_first, :after_second]
    end
  end

  describe "schema without hooks" do
    test "apply works normally without hooks" do
      state = NoHooksSchema.new!()

      new_state = NoHooksSchema.apply(state, {:increment})

      assert new_state.count == 1
      assert get_calls() == []
    end
  end

  describe "hooks with different actions" do
    test "hooks are called for all actions" do
      defmodule MultiActionSchema do
        use LiveSchema

        before_action(:track_action)

        schema do
          field :count, :integer, default: 0
          field :name, :string, default: ""
        end

        action :increment do
          set_count(state, state.count + 1)
        end

        action :set_name, [:new_name] do
          set_name(state, new_name)
        end

        def track_action(_state, action) do
          Agent.update(:hook_tracker, fn calls ->
            calls ++ [{:action, elem(action, 0)}]
          end)
        end
      end

      state = MultiActionSchema.new!()

      state = MultiActionSchema.apply(state, {:increment})
      state = MultiActionSchema.apply(state, {:set_name, "test"})
      _state = MultiActionSchema.apply(state, {:increment})

      calls = get_calls()

      assert calls == [
               {:action, :increment},
               {:action, :set_name},
               {:action, :increment}
             ]
    end
  end

  describe "hook side effects" do
    test "hooks can perform side effects" do
      defmodule SideEffectSchema do
        use LiveSchema

        after_action(:send_message)

        schema do
          field :count, :integer, default: 0
        end

        action :increment do
          set_count(state, state.count + 1)
        end

        def send_message(_old, new_state, _action) do
          send(self(), {:state_changed, new_state.count})
        end
      end

      state = SideEffectSchema.new!()
      SideEffectSchema.apply(state, {:increment})

      assert_receive {:state_changed, 1}
    end
  end

  describe "introspection" do
    test "hooks don't affect __live_schema__ introspection" do
      fields = MultipleHooksSchema.__live_schema__(:fields)
      assert :count in fields

      actions = MultipleHooksSchema.__live_schema__(:actions)
      assert :increment in actions
    end
  end
end
