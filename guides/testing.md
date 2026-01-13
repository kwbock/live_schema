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
describe "select_post/2 reducer" do
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

### assert_reducer_result/3

Asserts a reducer produces expected changes:

```elixir
test "increment increases count" do
  state = CounterState.new!(count: 0)

  # Assert specific field values
  assert_reducer_result(state, {:increment}, %{count: 1})
end

test "loading sets loading flag" do
  state = PostsState.new!()

  # Use function for complex assertions
  assert_reducer_result(state, {:start_loading}, fn new_state ->
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

## Testing with Diff

Use diff to verify specific changes:

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

  describe "select_post reducer" do
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

  describe "filter reducers" do
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
