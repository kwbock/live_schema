# Actions Guide

Actions provide an Elm-style pattern for state transitions. All complex state changes go through a central `apply/2` function.

## Basic Actions

```elixir
defmodule MyApp.CounterState do
  use LiveSchema

  schema do
    field :count, :integer, default: 0
  end

  action :increment do
    set_count(state, state.count + 1)
  end

  action :decrement do
    set_count(state, state.count - 1)
  end

  action :reset do
    set_count(state, 0)
  end
end
```

Usage:

```elixir
state = CounterState.new()
state = CounterState.apply(state, {:increment})  # count: 1
state = CounterState.apply(state, {:increment})  # count: 2
state = CounterState.apply(state, {:decrement})  # count: 1
state = CounterState.apply(state, {:reset})      # count: 0
```

## Actions with Arguments

```elixir
action :increment_by, [:amount] do
  set_count(state, state.count + amount)
end

action :select_post, [:id] do
  post = Enum.find(state.posts, &(&1.id == id))
  set_selected(state, post)
end
```

Usage:

```elixir
CounterState.apply(state, {:increment_by, 5})
PostsState.apply(state, {:select_post, 42})
```

## Guards and Pattern Matching

```elixir
action :increment_by, [:amount] when is_integer(amount) and amount > 0 do
  set_count(state, state.count + amount)
end

action :set_status, [:status] when status in [:pending, :active, :done] do
  set_status(state, status)
end
```

Invalid calls will raise `LiveSchema.ActionError`:

```elixir
CounterState.apply(state, {:increment_by, -1})
# ** (LiveSchema.ActionError) Unknown action :increment_by
#     Available actions: [:increment_by, ...]
```

## Multi-Field Updates

Reducers can update multiple fields at once:

```elixir
action :load_posts_success, [:posts] do
  state
  |> set_posts(posts)
  |> set_loading(false)
  |> set_error(nil)
end

action :apply_filter, [:filter_params] do
  state
  |> set_filter(struct(state.filter, filter_params))
  |> set_pagination(%{state.pagination | page: 1})
end
```

## Async Actions

For operations that need to perform async work:

```elixir
async_action :load_posts, [:filter] do
  # This code runs in a separate process
  posts = MyApp.Posts.list(filter)
  set_posts(state, posts)
end
```

Usage in LiveView:

```elixir
def handle_event("load", params, socket) do
  case State.apply(socket.assigns.state, {:load_posts, params}) do
    {:async, work_fn} ->
      {:noreply, start_async(socket, :load_posts, work_fn)}

    new_state ->
      {:noreply, assign(socket, :state, new_state)}
  end
end

def handle_async(:load_posts, {:ok, new_state}, socket) do
  {:noreply, assign(socket, :state, new_state)}
end

def handle_async(:load_posts, {:exit, reason}, socket) do
  state = State.apply(socket.assigns.state, {:load_error, reason})
  {:noreply, assign(socket, :state, state)}
end
```

## Middleware / Hooks

Add before and after hooks for cross-cutting concerns:

```elixir
defmodule MyApp.PostsState do
  use LiveSchema
  require Logger

  before_action :log_action
  after_action :emit_telemetry

  schema do
    field :posts, {:list, :any}, default: []
  end

  action :add_post, [:post] do
    set_posts(state, [post | state.posts])
  end

  # Before hooks receive (state, action)
  defp log_action(state, action) do
    Logger.debug("Dispatching #{inspect(action)}")
  end

  # After hooks receive (old_state, new_state, action)
  defp emit_telemetry(_old_state, _new_state, action) do
    :telemetry.execute(
      [:my_app, :state, :changed],
      %{},
      %{action: elem(action, 0)}
    )
  end
end
```

## Best Practices

### 1. Keep Actions Pure

Actions should be pure functions - avoid side effects:

```elixir
# Good - pure function
action :select_post, [:id] do
  post = Enum.find(state.posts, &(&1.id == id))
  set_selected(state, post)
end

# Bad - side effect in action
action :select_post, [:id] do
  post = Enum.find(state.posts, &(&1.id == id))
  Logger.info("Selected post #{id}")  # Don't do this!
  set_selected(state, post)
end
```

Use hooks for side effects instead.

### 2. Name Actions Descriptively

```elixir
# Good
action :mark_post_as_read, [:id] do ...
action :apply_search_filter, [:query] do ...

# Less clear
action :update, [:field, :value] do ...
action :do_action, [:data] do ...
```

### 3. Compose Small Actions

```elixir
action :load_complete, [:posts, :total_pages] do
  state
  |> apply_action({:set_posts, posts})
  |> apply_action({:set_loading, false})
  |> apply_action({:set_total_pages, total_pages})
end
```

### 4. Handle All States

Consider all possible state transitions:

```elixir
action :fetch_posts do
  set_loading(state, true)
end

action :fetch_posts_success, [:posts] do
  state
  |> set_posts(posts)
  |> set_loading(false)
  |> set_error(nil)
end

action :fetch_posts_error, [:reason] do
  state
  |> set_loading(false)
  |> set_error(reason)
end
```
