defmodule LiveSchemaTest do
  use ExUnit.Case, async: true
  doctest LiveSchema

  defmodule TestState do
    use LiveSchema

    schema do
      field :name, :string, default: ""
      field :count, :integer, default: 0
      field :active, :boolean, default: false
      field :tags, {:list, :string}, default: []
      field :metadata, :map, null: true
    end

    reducer :increment do
      set_count(state, state.count + 1)
    end

    reducer :increment_by, [:amount] when is_integer(amount) and amount > 0 do
      set_count(state, state.count + amount)
    end

    reducer :set_name, [:name] do
      set_name(state, name)
    end

    reducer :toggle_active do
      set_active(state, !state.active)
    end
  end

  describe "new/0" do
    test "creates state with defaults" do
      state = TestState.new!()

      assert state.name == ""
      assert state.count == 0
      assert state.active == false
      assert state.tags == []
      assert state.metadata == nil
    end
  end

  describe "new/1" do
    test "creates state with custom values" do
      {:ok, state} = TestState.new(name: "test", count: 5)

      assert state.name == "test"
      assert state.count == 5
    end

    test "ignores unknown fields" do
      {:ok, state} = TestState.new(unknown: "value")

      assert state.name == ""
    end
  end

  describe "setters" do
    test "set_name updates name" do
      state = TestState.new!()
      state = TestState.set_name(state, "updated")

      assert state.name == "updated"
    end

    test "set_count updates count" do
      state = TestState.new!()
      state = TestState.set_count(state, 42)

      assert state.count == 42
    end
  end

  describe "apply/2" do
    test "increment increases count by 1" do
      state = TestState.new!(count: 0)
      state = TestState.apply(state, {:increment})

      assert state.count == 1
    end

    test "increment_by increases count by amount" do
      state = TestState.new!(count: 0)
      state = TestState.apply(state, {:increment_by, 5})

      assert state.count == 5
    end

    test "set_name updates the name" do
      state = TestState.new!()
      state = TestState.apply(state, {:set_name, "hello"})

      assert state.name == "hello"
    end

    test "toggle_active flips the active flag" do
      state = TestState.new!(active: false)

      state = TestState.apply(state, {:toggle_active})
      assert state.active == true

      state = TestState.apply(state, {:toggle_active})
      assert state.active == false
    end

    test "raises ActionError for unknown action" do
      state = TestState.new!()

      assert_raise LiveSchema.ActionError, fn ->
        TestState.apply(state, {:unknown_action})
      end
    end
  end

  describe "__live_schema__/1" do
    test "returns field list" do
      fields = TestState.__live_schema__(:fields)

      assert :name in fields
      assert :count in fields
      assert :active in fields
    end

    test "returns field info" do
      info = TestState.__live_schema__({:field, :count})

      assert info.type == :integer
      assert info.default == 0
    end

    test "returns reducer list" do
      reducers = TestState.__live_schema__(:reducers)

      assert :increment in reducers
      assert :increment_by in reducers
    end
  end
end
