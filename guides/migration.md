# Migration Guide

This guide helps you migrate from raw assigns to LiveSchema.

## Why Migrate?

**Before (Raw Assigns):**
- State scattered across multiple assigns
- No type information
- Hard to test in isolation
- Easy to introduce typos

**After (LiveSchema):**
- Explicit state shape in one place
- Type specifications and optional validation
- State logic testable without LiveView
- Compile-time guarantees

## Step-by-Step Migration

### Step 1: Identify Current State

First, audit your LiveView to find all assigns:

```elixir
# Before: Typical LiveView with scattered assigns
def mount(_params, session, socket) do
  {:ok,
   socket
   |> assign(:user, get_user(session))
   |> assign(:posts, [])
   |> assign(:selected_post, nil)
   |> assign(:filter_status, :all)
   |> assign(:search_query, "")
   |> assign(:page, 1)
   |> assign(:loading, false)
   |> assign(:error, nil)
   |> assign(:show_modal, false)}
end
```

### Step 2: Group Related State

Identify groups of related state:

- **Business state**: posts, selected_post, filter_status, search_query, page
- **UI state**: loading, error, show_modal
- **Session state**: user

### Step 3: Create the Schema

```elixir
defmodule MyAppWeb.PostsLive.State do
  use LiveSchema

  schema do
    # Core data
    field :posts, {:list, :any}, default: []
    field :selected_post, {:nullable, :any}

    # Filter state (could be embeds_one)
    embeds_one :filter do
      field :status, {:enum, [:all, :published, :draft]}, default: :all
      field :search, :string, default: ""
    end

    # Pagination
    field :page, :integer, default: 1

    # UI state - keep simple fields at top level
    field :loading, :boolean, default: false
    field :error, {:nullable, :string}
  end
end
```

### Step 4: Define Reducers

Convert your event handlers' state logic into reducers:

```elixir
# Before: Logic in handle_event
def handle_event("filter", %{"status" => status}, socket) do
  status = String.to_existing_atom(status)
  posts = fetch_posts(status: status)
  {:noreply,
   socket
   |> assign(:filter_status, status)
   |> assign(:posts, posts)
   |> assign(:page, 1)}
end

# After: Logic in reducer
reducer :apply_filter, [:status] do
  posts = fetch_posts(status: status)

  state
  |> set_filter(%{state.filter | status: status})
  |> set_posts(posts)
  |> set_page(1)
end
```

### Step 5: Update the LiveView

```elixir
defmodule MyAppWeb.PostsLive do
  use MyAppWeb, :live_view
  use LiveSchema.View, schema: __MODULE__.State

  # Keep user as a separate assign (session data)
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:user, get_user(session))
     |> init_state()
     # UI-only state can stay as assigns
     |> assign(:show_modal, false)}
  end

  # Before
  def handle_event("filter", %{"status" => status}, socket) do
    status = String.to_existing_atom(status)
    posts = fetch_posts(status: status)
    {:noreply,
     socket
     |> assign(:filter_status, status)
     |> assign(:posts, posts)
     |> assign(:page, 1)}
  end

  # After
  def handle_event("filter", %{"status" => status}, socket) do
    status = String.to_existing_atom(status)
    {:noreply, apply_action(socket, {:apply_filter, status})}
  end
end
```

### Step 6: Update Templates

```heex
<%# Before %>
<%= for post <- @posts do %>
  <div class={if @selected_post && @selected_post.id == post.id, do: "selected"}>
    <%= post.title %>
  </div>
<% end %>

<%# After %>
<%= for post <- @state.posts do %>
  <div class={if @state.selected_post && @state.selected_post.id == post.id, do: "selected"}>
    <%= post.title %>
  </div>
<% end %>
```

### Step 7: Add Tests

```elixir
defmodule MyAppWeb.PostsLive.StateTest do
  use ExUnit.Case, async: true
  use LiveSchema.Test

  alias MyAppWeb.PostsLive.State

  test "apply_filter resets page" do
    state = State.new!(page: 5)

    new_state = State.apply(state, {:apply_filter, :published})

    assert new_state.filter.status == :published
    assert new_state.page == 1
  end
end
```

## Migration Checklist

- [ ] Audit all assigns in mount/handle_*/render
- [ ] Group related state
- [ ] Create State module with schema
- [ ] Convert state transitions to reducers
- [ ] Update LiveView to use LiveSchema.View
- [ ] Update templates to use @state
- [ ] Keep truly ephemeral UI state as assigns
- [ ] Add tests for state logic
- [ ] Remove unused assigns

## Common Patterns

### Session Data

Keep session data as separate assigns:

```elixir
def mount(_params, session, socket) do
  {:ok,
   socket
   |> assign(:current_user, get_user(session))  # Session data
   |> init_state()}  # LiveSchema state
end
```

### Modal State

Simple UI state can stay as assigns:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> init_state()
   |> assign(:show_modal, false)
   |> assign(:modal_content, nil)}
end

def handle_event("open_modal", %{"content" => content}, socket) do
  {:noreply,
   socket
   |> assign(:show_modal, true)
   |> assign(:modal_content, content)}
end
```

Or include in state if it affects business logic:

```elixir
schema do
  field :editing_post, {:nullable, :any}
end

reducer :start_editing, [:post] do
  set_editing_post(state, post)
end

reducer :cancel_editing do
  set_editing_post(state, nil)
end
```

### Derived State

Compute derived values in templates or with functions:

```elixir
# In State module
def post_count(%__MODULE__{posts: posts}), do: length(posts)

def filtered_posts(%__MODULE__{posts: posts, filter: filter}) do
  posts
  |> filter_by_status(filter.status)
  |> filter_by_search(filter.search)
end

# In template
<p>Showing <%= State.post_count(@state) %> posts</p>
<%= for post <- State.filtered_posts(@state) do %>
  ...
<% end %>
```

## Gradual Migration

You don't have to migrate everything at once:

1. Start with one LiveView
2. Keep existing assigns alongside @state
3. Gradually move assigns into the schema
4. Remove old assigns once moved

```elixir
# During migration - both patterns coexist
def mount(_params, session, socket) do
  {:ok,
   socket
   # New pattern
   |> init_state()
   # Old pattern (still works)
   |> assign(:legacy_data, load_legacy())}
end
```
