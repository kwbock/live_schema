# Getting Started

This guide walks you through installing LiveSchema and creating your first state module.

## Installation

Add `live_schema` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_schema, "~> 0.1.0"}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

## Your First Schema

Let's create a simple state module for a posts list view.

### 1. Define the State

Create a new file `lib/my_app/posts_state.ex`:

```elixir
defmodule MyApp.PostsState do
  use LiveSchema

  schema do
    field :posts, {:list, :any}, default: []
    field :selected, :any, null: true
    field :loading, :boolean, default: false
    field :error, :string, null: true
  end

  # Reducers for state transitions
  action :select_post, [:id] do
    post = Enum.find(state.posts, &(&1.id == id))
    set_selected(state, post)
  end

  action :set_loading, [:loading] do
    set_loading(state, loading)
  end

  action :load_posts_success, [:posts] do
    state
    |> set_posts(posts)
    |> set_loading(false)
    |> set_error(nil)
  end

  action :load_posts_error, [:message] do
    state
    |> set_loading(false)
    |> set_error(message)
  end
end
```

### 2. Use in a LiveView

```elixir
defmodule MyAppWeb.PostsLive do
  use MyAppWeb, :live_view
  use LiveSchema.View, schema: MyApp.PostsState

  alias MyApp.PostsState

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :load_posts)
    end

    {:ok, init_state(socket)}
  end

  def handle_info(:load_posts, socket) do
    socket = apply_action(socket, {:set_loading, true})

    case MyApp.Posts.list() do
      {:ok, posts} ->
        {:noreply, apply_action(socket, {:load_posts_success, posts})}

      {:error, reason} ->
        {:noreply, apply_action(socket, {:load_posts_error, reason})}
    end
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, apply_action(socket, {:select_post, String.to_integer(id)})}
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @state.loading do %>
        <p>Loading...</p>
      <% end %>

      <%= if @state.error do %>
        <p class="error"><%= @state.error %></p>
      <% end %>

      <ul>
        <%= for post <- @state.posts do %>
          <li
            phx-click="select"
            phx-value-id={post.id}
            class={if @state.selected && @state.selected.id == post.id, do: "selected"}
          >
            <%= post.title %>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
```

## What You Get

By using LiveSchema, you automatically get:

1. **Explicit State Shape**: All state fields are defined in one place
2. **Auto-generated Setters**: `set_posts/2`, `set_selected/2`, etc.
3. **Type Specs**: Proper `@type t` specification
4. **Constructors**: `new/0`, `new/1`, `new!/1`
5. **Introspection**: `__live_schema__/1` for tooling

## Next Steps

- [Schema DSL](schema-dsl.md) - Learn all the field options
- [Actions](actions.md) - Complex state transitions
- [Validation](validation.md) - Runtime type checking
- [Phoenix Integration](phoenix-integration.md) - LiveView and Component helpers
