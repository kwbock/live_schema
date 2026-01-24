# LiveSchema

A comprehensive state management library for Phoenix LiveView with DSL, type checking, and deep Phoenix integration.

## Features

- **Schema DSL** - Define your state structure with a clean, expressive syntax
- **Type System** - Built-in types with runtime validation
- **Auto-generated Setters** - Reduce boilerplate with automatic setter functions
- **Reducers** - Elm-style state transitions for complex updates
- **Phoenix Integration** - Seamless integration with LiveView and Components
- **Testing Utilities** - Helpers for testing state logic in isolation

## Installation

Add `live_schema` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_schema, "~> 0.0.1"}
  ]
end
```

## Quick Start

Define a state schema:

```elixir
defmodule MyAppWeb.PostsLive.State do
  use LiveSchema

  schema do
    field :posts, {:list, Post}, default: []
    field :selected, Post, null: true
    field :loading, :boolean, default: false

    embeds_one :filter do
      field :status, {:enum, [:all, :active, :archived]}, default: :all
      field :search, :string, default: ""
    end
  end

  reducer :select_post, [:id] do
    post = Enum.find(state.posts, &(&1.id == id))
    set_selected(state, post)
  end

  reducer :update_filter, [:field, :value] do
    update_in(state.filter, &Map.put(&1, field, value))
  end
end
```

Use in your LiveView:

```elixir
defmodule MyAppWeb.PostsLive do
  use MyAppWeb, :live_view
  use LiveSchema.View, schema: __MODULE__.State

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :state, State.new())}
  end

  def handle_event("select", %{"id" => id}, socket) do
    state = State.apply(socket.assigns.state, {:select_post, String.to_integer(id)})
    {:noreply, assign(socket, :state, state)}
  end
end
```

## Documentation

- [Getting Started](guides/getting-started.md)
- [Schema DSL](guides/schema-dsl.md)
- [Reducers](guides/reducers.md)
- [Validation](guides/validation.md)
- [Phoenix Integration](guides/phoenix-integration.md)
- [Testing](guides/testing.md)

## License

MIT License - see [LICENSE](LICENSE) for details.
