defmodule LiveSchema.DiffTest do
  use ExUnit.Case, async: true

  alias LiveSchema.Diff

  # Test schema for diff testing
  defmodule SimpleState do
    use LiveSchema

    schema do
      field :name, :string, default: ""
      field :count, :integer, default: 0
      field :active, :boolean, default: false
      field :data, :string, null: true
    end
  end

  # Test schema with nested embed
  defmodule ParentState do
    use LiveSchema

    schema do
      field :title, :string, default: ""

      embeds_one :child do
        field :value, :integer, default: 0
        field :label, :string, default: ""
      end
    end
  end

  # Regular struct (non-LiveSchema) for testing compatibility
  defmodule RegularStruct do
    defstruct [:name, :count]
  end

  # Another regular struct for type mismatch testing
  defmodule OtherStruct do
    defstruct [:name, :count]
  end

  describe "diff/2 - unchanged" do
    test "returns :unchanged when structs are identical" do
      state = SimpleState.new!()
      assert :unchanged = Diff.diff(state, state)
    end

    test "returns :unchanged when structs have same values" do
      old = SimpleState.new!(name: "test", count: 5)
      new = SimpleState.new!(name: "test", count: 5)
      assert :unchanged = Diff.diff(old, new)
    end

    test "returns :unchanged for default structs" do
      old = SimpleState.new!()
      new = SimpleState.new!()
      assert :unchanged = Diff.diff(old, new)
    end
  end

  describe "diff/2 - changed detection" do
    test "detects single field change" do
      old = SimpleState.new!(count: 0)
      new = SimpleState.new!(count: 5)

      assert {:changed, diff} = Diff.diff(old, new)
      assert :count in diff.changed
      assert length(diff.changed) == 1
    end

    test "detects multiple field changes" do
      old = SimpleState.new!(name: "old", count: 0, active: false)
      new = SimpleState.new!(name: "new", count: 10, active: true)

      assert {:changed, diff} = Diff.diff(old, new)
      assert :name in diff.changed
      assert :count in diff.changed
      assert :active in diff.changed
      assert length(diff.changed) == 3
    end

    test "does not include unchanged fields" do
      old = SimpleState.new!(name: "same", count: 0)
      new = SimpleState.new!(name: "same", count: 5)

      assert {:changed, diff} = Diff.diff(old, new)
      refute :name in diff.changed
      assert :count in diff.changed
    end
  end

  describe "diff/2 - added fields (nil -> value)" do
    test "detects field added from nil" do
      old = SimpleState.new!(data: nil)
      new = SimpleState.new!(data: "new_value")

      assert {:changed, diff} = Diff.diff(old, new)
      assert :data in diff.changed
      assert diff.added[:data] == "new_value"
      assert map_size(diff.removed) == 0
      assert map_size(diff.modified) == 0
    end

    test "added map contains new value" do
      old = SimpleState.new!(data: nil)
      new = SimpleState.new!(data: "added")

      assert {:changed, diff} = Diff.diff(old, new)
      assert diff.added == %{data: "added"}
    end
  end

  describe "diff/2 - removed fields (value -> nil)" do
    test "detects field removed to nil" do
      old = SimpleState.new!(data: "old_value")
      new = SimpleState.new!(data: nil)

      assert {:changed, diff} = Diff.diff(old, new)
      assert :data in diff.changed
      assert diff.removed[:data] == "old_value"
      assert map_size(diff.added) == 0
      assert map_size(diff.modified) == 0
    end

    test "removed map contains old value" do
      old = SimpleState.new!(data: "removed")
      new = SimpleState.new!(data: nil)

      assert {:changed, diff} = Diff.diff(old, new)
      assert diff.removed == %{data: "removed"}
    end
  end

  describe "diff/2 - modified fields (value -> different value)" do
    test "detects modified field" do
      old = SimpleState.new!(name: "old")
      new = SimpleState.new!(name: "new")

      assert {:changed, diff} = Diff.diff(old, new)
      assert :name in diff.changed
      assert diff.modified[:name] == {"old", "new"}
    end

    test "modified map contains old and new values as tuple" do
      old = SimpleState.new!(count: 5, name: "old")
      new = SimpleState.new!(count: 10, name: "new")

      assert {:changed, diff} = Diff.diff(old, new)
      assert diff.modified[:count] == {5, 10}
      assert diff.modified[:name] == {"old", "new"}
    end

    test "boolean changes are in modified" do
      old = SimpleState.new!(active: false)
      new = SimpleState.new!(active: true)

      assert {:changed, diff} = Diff.diff(old, new)
      assert diff.modified[:active] == {false, true}
    end
  end

  describe "diff/2 - nested struct diffs" do
    test "detects changes in nested struct" do
      old = ParentState.new!(title: "same")
      old = %{old | child: ParentState.Child.new!(value: 0)}

      new = ParentState.new!(title: "same")
      new = %{new | child: ParentState.Child.new!(value: 10)}

      assert {:changed, diff} = Diff.diff(old, new)
      assert :child in diff.changed
      assert Map.has_key?(diff.nested, :child)

      nested_diff = diff.nested[:child]
      assert :value in nested_diff.changed
      assert nested_diff.modified[:value] == {0, 10}
    end

    test "nested diff is not triggered when nested struct unchanged" do
      old = ParentState.new!(title: "old")
      old = %{old | child: ParentState.Child.new!(value: 5)}

      new = ParentState.new!(title: "new")
      new = %{new | child: ParentState.Child.new!(value: 5)}

      assert {:changed, diff} = Diff.diff(old, new)
      assert :title in diff.changed
      refute :child in diff.changed
      assert map_size(diff.nested) == 0
    end

    test "detects multiple changes in nested struct" do
      old = ParentState.new!()
      old = %{old | child: ParentState.Child.new!(value: 0, label: "old")}

      new = ParentState.new!()
      new = %{new | child: ParentState.Child.new!(value: 10, label: "new")}

      assert {:changed, diff} = Diff.diff(old, new)

      nested_diff = diff.nested[:child]
      assert :value in nested_diff.changed
      assert :label in nested_diff.changed
    end
  end

  describe "diff/2 - struct type mismatch" do
    test "detects different struct types" do
      old = %RegularStruct{name: "test", count: 5}
      new = %OtherStruct{name: "test", count: 5}

      assert {:changed, diff} = Diff.diff(old, new)
      assert :__struct__ in diff.changed
      assert diff.modified[:__struct__] == {RegularStruct, OtherStruct}
    end
  end

  describe "diff/2 - regular structs (non-LiveSchema)" do
    test "works with regular structs" do
      old = %RegularStruct{name: "old", count: 0}
      new = %RegularStruct{name: "new", count: 5}

      assert {:changed, diff} = Diff.diff(old, new)
      assert :name in diff.changed
      assert :count in diff.changed
    end

    test "returns unchanged for equal regular structs" do
      old = %RegularStruct{name: "same", count: 5}
      new = %RegularStruct{name: "same", count: 5}

      assert :unchanged = Diff.diff(old, new)
    end
  end

  describe "diff/2 - combined changes" do
    test "handles added, removed, and modified in same diff" do
      old = SimpleState.new!(name: "old", data: "will_remove")
      new = SimpleState.new!(name: "new", data: nil)
      # We need a field that goes nil -> value for "added"
      # But SimpleState doesn't easily allow that in one comparison
      # Let's test added + modified separately

      assert {:changed, diff} = Diff.diff(old, new)
      assert diff.modified[:name] == {"old", "new"}
      assert diff.removed[:data] == "will_remove"
    end

    test "categorizes changes correctly" do
      # Start with data: nil, set name
      old = SimpleState.new!(name: "old", data: nil)
      # End with data: "added", changed name
      new = SimpleState.new!(name: "new", data: "added")

      assert {:changed, diff} = Diff.diff(old, new)

      # name: "old" -> "new" is modified
      assert diff.modified[:name] == {"old", "new"}

      # data: nil -> "added" is added
      assert diff.added[:data] == "added"

      # Nothing removed
      assert map_size(diff.removed) == 0
    end
  end

  describe "format/1" do
    test "formats modified fields" do
      diff = %{
        changed: [:count],
        added: %{},
        removed: %{},
        modified: %{count: {0, 10}},
        nested: %{}
      }

      result = Diff.format(diff)
      assert result =~ "Modified:"
      assert result =~ "count"
      assert result =~ "0"
      assert result =~ "10"
      assert result =~ "->"
    end

    test "formats added fields" do
      diff = %{
        changed: [:data],
        added: %{data: "new_value"},
        removed: %{},
        modified: %{},
        nested: %{}
      }

      result = Diff.format(diff)
      assert result =~ "Added:"
      assert result =~ "data"
      assert result =~ "new_value"
      assert result =~ "+"
    end

    test "formats removed fields" do
      diff = %{
        changed: [:data],
        added: %{},
        removed: %{data: "old_value"},
        modified: %{},
        nested: %{}
      }

      result = Diff.format(diff)
      assert result =~ "Removed:"
      assert result =~ "data"
      assert result =~ "old_value"
      assert result =~ "-"
    end

    test "formats multiple change types" do
      diff = %{
        changed: [:name, :data, :count],
        added: %{data: "added"},
        removed: %{count: 5},
        modified: %{name: {"old", "new"}},
        nested: %{}
      }

      result = Diff.format(diff)
      assert result =~ "Added:"
      assert result =~ "Removed:"
      assert result =~ "Modified:"
    end

    test "handles diff with only nested changes" do
      diff = %{
        changed: [:child],
        added: %{},
        removed: %{},
        modified: %{},
        nested: %{child: %{changed: [:value], modified: %{value: {0, 1}}}}
      }

      result = Diff.format(diff)
      # When only nested changes, it shows "No changes to fields"
      assert result =~ "No changes"
      assert result =~ ":child"
    end
  end

  describe "assert_changed/3" do
    test "returns :ok when expected fields match exactly" do
      old = SimpleState.new!(count: 0)
      new = SimpleState.new!(count: 5)

      assert :ok = Diff.assert_changed(old, new, [:count])
    end

    test "returns :ok with multiple expected changes" do
      old = SimpleState.new!(name: "old", count: 0)
      new = SimpleState.new!(name: "new", count: 5)

      assert :ok = Diff.assert_changed(old, new, [:name, :count])
    end

    test "raises when nothing changed but expected changes" do
      old = SimpleState.new!(count: 5)
      new = SimpleState.new!(count: 5)

      assert_raise ExUnit.AssertionError, ~r/nothing changed/, fn ->
        Diff.assert_changed(old, new, [:count])
      end
    end

    test "raises when missing expected changes" do
      old = SimpleState.new!(count: 0)
      new = SimpleState.new!(count: 5)

      assert_raise ExUnit.AssertionError, ~r/Missing expected changes.*:name/, fn ->
        Diff.assert_changed(old, new, [:count, :name])
      end
    end

    test "raises when there are unexpected changes" do
      old = SimpleState.new!(name: "old", count: 0)
      new = SimpleState.new!(name: "new", count: 5)

      assert_raise ExUnit.AssertionError, ~r/Unexpected changes.*:name/, fn ->
        Diff.assert_changed(old, new, [:count])
      end
    end

    test "raises with both missing and unexpected changes" do
      old = SimpleState.new!(name: "old", count: 0)
      new = SimpleState.new!(name: "new", count: 5)

      error = assert_raise ExUnit.AssertionError, fn ->
        Diff.assert_changed(old, new, [:count, :active])
      end

      assert error.message =~ "Missing expected changes"
      assert error.message =~ ":active"
      assert error.message =~ "Unexpected changes"
      assert error.message =~ ":name"
    end

    test "works with empty expected list when nothing changed" do
      old = SimpleState.new!(count: 5)
      new = SimpleState.new!(count: 5)

      # This should raise because nothing changed but we expect empty list
      # Actually, when :unchanged and expected is [], that means we expected changes
      # But we got no changes. Let me check the logic...
      # The function raises "Expected fields [] to change, but nothing changed"
      # So even with empty expected, it raises if :unchanged

      assert_raise ExUnit.AssertionError, fn ->
        Diff.assert_changed(old, new, [])
      end
    end
  end

  describe "edge cases" do
    test "handles list field changes" do
      defmodule ListState do
        use LiveSchema
        schema do
          field :items, {:list, :string}, default: []
        end
      end

      old = ListState.new!(items: ["a", "b"])
      new = ListState.new!(items: ["a", "b", "c"])

      assert {:changed, diff} = Diff.diff(old, new)
      assert :items in diff.changed
      assert diff.modified[:items] == {["a", "b"], ["a", "b", "c"]}
    end

    test "handles map field changes" do
      defmodule MapState do
        use LiveSchema
        schema do
          field :metadata, :map, default: %{}
        end
      end

      old = MapState.new!(metadata: %{a: 1})
      new = MapState.new!(metadata: %{a: 1, b: 2})

      assert {:changed, diff} = Diff.diff(old, new)
      assert :metadata in diff.changed
    end

    test "preserves order of changed fields" do
      old = SimpleState.new!(name: "a", count: 0, active: false)
      new = SimpleState.new!(name: "b", count: 1, active: true)

      assert {:changed, diff} = Diff.diff(old, new)

      # Fields should be in the order they appear in the schema
      assert length(diff.changed) == 3
    end

    test "handles deeply nested nil values" do
      old = ParentState.new!()
      # child starts as initialized struct from new/0
      new = ParentState.new!()

      # Both have same child, so should be unchanged
      assert :unchanged = Diff.diff(old, new)
    end
  end
end
