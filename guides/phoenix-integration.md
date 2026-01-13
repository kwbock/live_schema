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

    reducer :set_posts, [:posts] do
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

Applies a reducer action:

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

## Form Integration

### Building Forms

```elixir
defmodule MyAppWeb.UserLive do
  use MyAppWeb, :live_view
  alias MyApp.UserState

  def mount(_params, _session, socket) do
    state = UserState.new()
    form = LiveSchema.Form.to_form(state, as: :user)
    {:ok, assign(socket, state: state, form: form)}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.state
      |> LiveSchema.change()
      |> LiveSchema.Form.cast(params, [:name, :email, :age])
      |> LiveSchema.validate()

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case socket.assigns.state
         |> LiveSchema.change()
         |> LiveSchema.Form.cast(params, [:name, :email, :age])
         |> LiveSchema.validate()
         |> LiveSchema.apply() do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(state: new_state)
         |> put_flash(:info, "Saved!")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  def render(assigns) do
    ~H"""
    <.form for={@form} phx-change="validate" phx-submit="save">
      <.input field={@form[:name]} label="Name" />
      <.input field={@form[:email]} label="Email" type="email" />
      <.input field={@form[:age]} label="Age" type="number" />
      <.button>Save</.button>
    </.form>
    """
  end
end
```

### Converting Between State and Params

```elixir
# State to form params
params = LiveSchema.Form.state_to_params(state)
# %{"name" => "John", "email" => "john@example.com"}

# Params to state
{:ok, state} = LiveSchema.Form.params_to_state(UserState, params)
```

## PubSub Integration

### Setting Up Sync

```elixir
defmodule MyApp.PostsState do
  use LiveSchema

  @pubsub MyApp.PubSub
  @topic "posts"

  schema do
    field :posts, {:list, :any}, default: []
  end

  reducer :add_post, [:post] do
    new_state = set_posts(state, [post | state.posts])

    # Broadcast to other processes
    LiveSchema.PubSub.broadcast_from(
      self(),
      @pubsub,
      @topic,
      :posts,
      new_state.posts
    )

    new_state
  end
end
```

### Subscribing in LiveView

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    LiveSchema.PubSub.subscribe(MyApp.PubSub, "posts")
  end

  {:ok, init_state(socket)}
end

def handle_info({:live_schema_sync, :posts, posts}, socket) do
  {:noreply, update_state(socket, &State.set_posts(&1, posts))}
end
```

### Scoped Topics

For resource-specific sync:

```elixir
# Subscribe to a specific post's comments
topic = LiveSchema.PubSub.topic("post_comments", post_id)
LiveSchema.PubSub.subscribe(MyApp.PubSub, topic)

# Broadcast updates
LiveSchema.PubSub.broadcast(MyApp.PubSub, topic, :comments, updated_comments)
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
    [:live_schema, :reducer, :stop],
    &MyApp.Telemetry.handle_reducer/4,
    nil
  )

  # ...
end
```

Events emitted:

- `[:live_schema, :reducer, :start]` - Before reducer execution
- `[:live_schema, :reducer, :stop]` - After successful execution
- `[:live_schema, :reducer, :exception]` - On error
- `[:live_schema, :validation, :failure]` - On validation failure
