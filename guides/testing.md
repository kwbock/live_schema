# Testing Guide

LiveSchema provides utilities for testing state modules in isolation.

## Setup

Add to your test helper:

```elixir
# test/test_helper.exs
ExUnit.start()
```

In your tests:

```elixir
defmodule MyApp.PostsStateTest do
  use ExUnit.Case, async: true
  use LiveSchema.Test

  alias MyApp.PostsState
end
```

## Testing State in Isolation

The main benefit of LiveSchema is that state logic can be tested without LiveView:

```elixir
describe "select_post/2 action" do
  test "selects a post by id" do
    posts = [
      %{id: 1, title: "First"},
      %{id: 2, title: "Second"}
    ]

    state = PostsState.new!(posts: posts)

    new_state = PostsState.apply(state, {:select_post, 2})

    assert new_state.selected.id == 2
    assert new_state.selected.title == "Second"
  end

  test "sets selected to nil when post not found" do
    state = PostsState.new!(posts: [%{id: 1, title: "First"}])

    new_state = PostsState.apply(state, {:select_post, 999})

    assert new_state.selected == nil
  end
end
```

## Assertion Helpers

### assert_valid_state/1

Verifies all validations pass:

```elixir
test "new state is valid" do
  state = PostsState.new!()
  assert_valid_state(state)
end
```

### assert_action_result/3

Asserts an action produces expected changes:

```elixir
test "increment increases count" do
  state = CounterState.new!(count: 0)

  # Assert specific field values
  assert_action_result(state, {:increment}, %{count: 1})
end

test "loading sets loading flag" do
  state = PostsState.new!()

  # Use function for complex assertions
  assert_action_result(state, {:start_loading}, fn new_state ->
    assert new_state.loading == true
    assert new_state.error == nil
  end)
end
```

### refute_reduces/2

Verifies invalid actions are rejected:

```elixir
test "rejects negative increment" do
  state = CounterState.new!()

  refute_reduces(state, {:increment, -1})
end

test "rejects unknown action" do
  state = PostsState.new!()

  refute_reduces(state, {:unknown_action})
end
```

### assert_fields_changed/3

Verifies exactly which fields changed:

```elixir
test "select_post only changes selected field" do
  state = PostsState.new!(posts: [%{id: 1}])
  new_state = PostsState.apply(state, {:select_post, 1})

  assert_fields_changed(state, new_state, [:selected])
end
```

## Factory Helpers

### build/2

Quick factory function:

```elixir
test "with custom attributes" do
  state = build(PostsState, posts: [%{id: 1}], loading: true)

  assert length(state.posts) == 1
  assert state.loading == true
end
```

## Property-Based Testing

With StreamData for property-based tests:

```elixir
use ExUnitProperties

property "count is always non-negative after increment" do
  check all initial <- integer(0..1000),
            amount <- positive_integer(),
            max_runs: 100 do
    state = CounterState.new!(count: initial)
    new_state = CounterState.apply(state, {:increment, amount})

    assert new_state.count == initial + amount
    assert new_state.count >= 0
  end
end
```

### Schema Generators

Generate random valid states:

```elixir
property "serialization roundtrip" do
  check all state <- schema_generator(PostsState) do
    json = Jason.encode!(state)
    decoded = Jason.decode!(json)

    # Properties should hold for any valid state
    assert is_list(decoded["posts"])
  end
end
```

## Testing Async Reducers

```elixir
test "load_posts fetches and sets posts" do
  state = PostsState.new!()

  # Get the async work function
  {:async, work_fn} = PostsState.apply(state, {:load_posts, %{}})

  # Execute the work (in test, this is synchronous)
  new_state = work_fn.()

  assert length(new_state.posts) > 0
  assert new_state.loading == false
end
```

### Mocking Async Operations

```elixir
test "load_posts handles errors" do
  mock_async :load_posts, fn _filter ->
    raise "Network error"
  end

  state = PostsState.new!()
  {:async, work_fn} = PostsState.apply(state, {:load_posts, %{}})

  assert_raise RuntimeError, "Network error", fn ->
    work_fn.()
  end
end
```

## State Diffing

LiveSchema provides `LiveSchema.Diff` for computing differences between state structs. This is useful for testing, debugging, and production optimizations.

### Basic Usage

```elixir
old_state = PostsState.new!(count: 0, name: "test")
new_state = PostsState.apply(old_state, {:increment})

case LiveSchema.diff(old_state, new_state) do
  :unchanged ->
    # States are identical
    :noop

  {:changed, diff} ->
    # diff contains details about what changed
    IO.inspect(diff.changed)   # [:count]
    IO.inspect(diff.modified)  # %{count: {0, 1}}
end
```

### The Diff Structure

When changes are detected, `diff/2` returns `{:changed, diff}` where diff contains:

- `changed` - List of field names that changed
- `added` - Map of fields that went from `nil` to a value
- `removed` - Map of fields that went from a value to `nil`
- `modified` - Map of fields that changed from one value to another (as `{old, new}` tuples)
- `nested` - Map of diffs for nested embedded structs

```elixir
{:changed, diff} = LiveSchema.diff(old_state, new_state)

diff.changed   #=> [:name, :count, :metadata]
diff.added     #=> %{metadata: %{key: "value"}}
diff.removed   #=> %{}
diff.modified  #=> %{name: {"old", "new"}, count: {0, 5}}
diff.nested    #=> %{settings: %{changed: [:theme], ...}}
```

### Formatting Diffs

Use `format/1` for human-readable output:

```elixir
{:changed, diff} = LiveSchema.diff(old_state, new_state)
IO.puts(LiveSchema.Diff.format(diff))

# Output:
# Added:
#   + metadata: %{key: "value"}
#
# Modified:
#   ~ name: "old" -> "new"
#   ~ count: 0 -> 5
```

### Testing with Diff

Use diff to verify specific changes in tests:

```elixir
test "filter change resets pagination" do
  state = PostsState.new!(
    filter: %{status: :all},
    pagination: %{page: 5}
  )

  new_state = PostsState.apply(state, {:set_filter_status, :active})

  {:changed, diff} = LiveSchema.diff(state, new_state)

  assert :filter in diff.changed
  assert :pagination in diff.changed
  assert new_state.pagination.page == 1
end
```

### assert_changed/3

For stricter test assertions, use `assert_changed/3` to verify exactly which fields changed:

```elixir
test "increment only modifies count" do
  old = CounterState.new!(count: 0, name: "test")
  new = CounterState.apply(old, {:increment})

  # Passes only if exactly these fields changed (no more, no less)
  LiveSchema.Diff.assert_changed(old, new, [:count])
end
```

## Production Use Cases for Diff

Beyond testing, state diffing enables several production optimizations.

### Debugging State Changes

Track what changed during complex action chains:

```elixir
defmodule MyApp.StateDebugger do
  require Logger

  def apply_with_logging(state, action) do
    new_state = MyState.apply(state, action)

    case LiveSchema.diff(state, new_state) do
      :unchanged ->
        Logger.debug("Action #{inspect(action)} produced no changes")

      {:changed, diff} ->
        Logger.debug("""
        Action: #{inspect(action)}
        Changed fields: #{inspect(diff.changed)}
        #{LiveSchema.Diff.format(diff)}
        """)
    end

    new_state
  end
end
```

### Optimized Re-rendering

Only push updates for fields that actually changed, minimizing DOM patches:

```elixir
def handle_event("update", params, socket) do
  old = socket.assigns.state
  new = MyState.apply(old, {:update, params})

  case LiveSchema.diff(old, new) do
    :unchanged ->
      {:noreply, socket}

    {:changed, %{changed: fields}} ->
      # Only send changed data to the client
      changes = Map.take(Map.from_struct(new), fields)
      {:noreply, push_event(socket, "state_update", changes)}
  end
end
```

### Audit Logging

Record what users changed for compliance, debugging, or activity feeds:

```elixir
defmodule MyApp.AuditLog do
  def apply_with_audit(state, action, user_id) do
    new_state = MyState.apply(state, action)

    case LiveSchema.diff(state, new_state) do
      {:changed, diff} ->
        %AuditEntry{
          user_id: user_id,
          action: action,
          changed_fields: diff.changed,
          old_values: extract_old_values(diff),
          new_values: extract_new_values(diff),
          timestamp: DateTime.utc_now()
        }
        |> MyApp.Repo.insert!()

      :unchanged ->
        :ok
    end

    new_state
  end

  defp extract_old_values(diff) do
    diff.modified
    |> Enum.map(fn {field, {old, _new}} -> {field, old} end)
    |> Map.new()
    |> Map.merge(diff.removed)
  end

  defp extract_new_values(diff) do
    diff.modified
    |> Enum.map(fn {field, {_old, new}} -> {field, new} end)
    |> Map.new()
    |> Map.merge(diff.added)
  end
end
```

### Undo/Redo Systems

Store minimal diffs instead of full state snapshots for memory efficiency:

```elixir
defmodule MyApp.UndoStack do
  defstruct undo: [], redo: []

  def push(stack, old_state, new_state) do
    case LiveSchema.diff(old_state, new_state) do
      :unchanged ->
        stack

      {:changed, diff} ->
        %{stack | undo: [{diff, old_state, new_state} | stack.undo], redo: []}
    end
  end

  def undo(%{undo: [{_diff, old_state, _new_state} | rest]} = stack) do
    {old_state, %{stack | undo: rest, redo: [old_state | stack.redo]}}
  end

  def undo(stack), do: {nil, stack}

  def redo(%{redo: [state | rest]} = stack) do
    {state, %{stack | redo: rest}}
  end

  def redo(stack), do: {nil, stack}
end
```

### Selective Persistence

Only persist fields that changed to reduce database writes:

```elixir
defmodule MyApp.StatePersistence do
  def persist_changes(old_state, new_state, record_id) do
    case LiveSchema.diff(old_state, new_state) do
      :unchanged ->
        :ok

      {:changed, diff} ->
        # Build changeset with only modified fields
        changes =
          diff.modified
          |> Enum.map(fn {field, {_old, new}} -> {field, new} end)
          |> Map.new()
          |> Map.merge(diff.added)

        if map_size(changes) > 0 do
          MyApp.Repo.get!(MySchema, record_id)
          |> Ecto.Changeset.change(changes)
          |> MyApp.Repo.update!()
        end
    end
  end
end
```

### Real-time Sync

Broadcast only changed fields to connected clients:

```elixir
defmodule MyApp.StateSync do
  def broadcast_changes(old_state, new_state, topic) do
    case LiveSchema.diff(old_state, new_state) do
      :unchanged ->
        :ok

      {:changed, diff} ->
        # Send minimal payload over the wire
        payload = %{
          changed: diff.changed,
          values: get_new_values(new_state, diff.changed)
        }

        Phoenix.PubSub.broadcast(MyApp.PubSub, topic, {:state_changed, payload})
    end
  end

  defp get_new_values(state, fields) do
    Map.take(Map.from_struct(state), fields)
  end
end
```

## Complete Test Example

```elixir
defmodule MyApp.PostsStateTest do
  use ExUnit.Case, async: true
  use LiveSchema.Test

  alias MyApp.PostsState

  describe "new/0" do
    test "creates state with defaults" do
      state = PostsState.new!()

      assert state.posts == []
      assert state.selected == nil
      assert state.loading == false
      assert_valid_state(state)
    end
  end

  describe "select_post action" do
    setup do
      posts = [
        %{id: 1, title: "First Post"},
        %{id: 2, title: "Second Post"}
      ]

      {:ok, state: PostsState.new!(posts: posts)}
    end

    test "selects existing post", %{state: state} do
      new_state = PostsState.apply(state, {:select_post, 1})

      assert new_state.selected.id == 1
      assert_fields_changed(state, new_state, [:selected])
    end

    test "clears selection for non-existent post", %{state: state} do
      new_state = PostsState.apply(state, {:select_post, 999})

      assert new_state.selected == nil
    end
  end

  describe "filter actions" do
    test "applying filter resets to page 1" do
      state = build(PostsState,
        filter: %{status: :all},
        pagination: %{page: 3}
      )

      new_state = PostsState.apply(state, {:filter_by_status, :active})

      assert new_state.filter.status == :active
      assert new_state.pagination.page == 1
    end
  end
end
```
