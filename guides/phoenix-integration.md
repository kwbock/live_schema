# Phoenix Integration Guide

LiveSchema provides deep integration with Phoenix LiveView and Components.

## LiveView Integration

### Basic Setup

```elixir
defmodule MyAppWeb.PostsLive do
  use MyAppWeb, :live_view
  use LiveSchema.View, schema: __MODULE__.State

  defmodule State do
    use LiveSchema

    schema do
      field :posts, {:list, :any}, default: []
      field :loading, :boolean, default: false
    end

    action :set_posts, [:posts] do
      state
      |> set_posts(posts)
      |> set_loading(false)
    end
  end

  def mount(_params, _session, socket) do
    {:ok, init_state(socket)}
  end

  def handle_event("refresh", _, socket) do
    {:noreply, apply_action(socket, {:set_loading, true})}
  end
end
```

### Available Helpers

#### `init_state/1`

Initializes the `@state` assign with a new state:

```elixir
def mount(_params, _session, socket) do
  {:ok, init_state(socket)}
end
```

#### `init_state/2`

Initializes with custom attributes:

```elixir
def mount(_params, session, socket) do
  {:ok, init_state(socket, user: session["user"])}
end
```

#### `apply_action/2`

Applies an action:

```elixir
def handle_event("select", %{"id" => id}, socket) do
  {:noreply, apply_action(socket, {:select_post, String.to_integer(id)})}
end
```

#### `update_state/2`

Updates state with a function:

```elixir
def handle_info({:new_post, post}, socket) do
  {:noreply, update_state(socket, fn state ->
    State.set_posts(state, [post | state.posts])
  end)}
end
```

## Telemetry Events

LiveSchema emits telemetry events for observability:

```elixir
# In your application.ex
def start(_type, _args) do
  # Attach default handlers for logging
  LiveSchema.Telemetry.attach_default_handlers()

  # Or attach custom handlers
  :telemetry.attach(
    "my-handler",
    [:live_schema, :action, :stop],
    &MyApp.Telemetry.handle_action/4,
    nil
  )

  # ...
end
```

Events emitted:

- `[:live_schema, :action, :start]` - Before action execution
- `[:live_schema, :action, :stop]` - After successful execution
- `[:live_schema, :action, :exception]` - On error
- `[:live_schema, :validation, :failure]` - On validation failure
