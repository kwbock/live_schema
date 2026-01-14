# Schema DSL Reference

The schema DSL provides a declarative way to define your state structure.

## Basic Fields

```elixir
schema do
  field :name, :string
  field :count, :integer, default: 0
  field :active, :boolean, default: false
end
```

## Type System

### Primitive Types

| Type | Elixir Type | Example Value |
|------|-------------|---------------|
| `:string` | `String.t()` | `"hello"` |
| `:integer` | `integer()` | `42` |
| `:float` | `float()` | `3.14` |
| `:boolean` | `boolean()` | `true` |
| `:atom` | `atom()` | `:active` |
| `:any` | `any()` | anything |
| `:map` | `map()` | `%{key: "value"}` |
| `:list` | `list()` | `[1, 2, 3]` |

### Parameterized Types

```elixir
# List of specific type
field :posts, {:list, {:struct, Post}}

# Nullable (value or nil) - use null: true option
field :selected, {:struct, Post}, null: true

# Enum (one of specific values)
field :status, {:enum, [:pending, :active, :done]}

# Struct reference
field :user, {:struct, User}

# Map with typed keys/values
field :scores, {:map, :string, :integer}

# Tuple with typed elements
field :point, {:tuple, [:float, :float]}
```

## Field Options

### default

Sets the default value for the field:

```elixir
field :count, :integer, default: 0
field :items, {:list, :any}, default: []
field :status, {:enum, [:draft, :published]}, default: :draft
```

### required

Marks a field as required (must be non-nil after initialization):

```elixir
field :user_id, :integer, required: true
```

### validate

Custom validation function or list of validators:

```elixir
field :email, :string, validate: [
  format: ~r/@/,
  length: [min: 5, max: 255]
]

field :age, :integer, validate: [
  number: [greater_than_or_equal_to: 0, less_than: 150]
]

field :username, :string, validate: &valid_username?/1
```

### setter

Customize the generated setter name or disable it:

```elixir
field :internal_id, :string, setter: false  # No setter generated
field :name, :string, setter: :update_name  # Custom name
```

### doc

Documentation string for the field:

```elixir
field :api_key, :string, doc: "The user's API key for external services"
```

### redact

Hide the field value in inspect output:

```elixir
field :password, :string, redact: true
field :token, :string, redact: true
```

## Embeds

### embeds_one

Defines a nested struct:

```elixir
schema do
  field :title, :string

  embeds_one :filter do
    field :status, {:enum, [:all, :active, :archived]}, default: :all
    field :search, :string, default: ""
  end
end
```

Or reference an existing module:

```elixir
schema do
  embeds_one :pagination, MyApp.Pagination
end
```

### embeds_many

Defines a list of nested structs:

```elixir
schema do
  embeds_many :tags do
    field :name, :string
    field :color, :string, default: "#000000"
  end
end
```

## Complete Example

```elixir
defmodule MyApp.PostsState do
  use LiveSchema

  schema do
    # Basic fields
    field :current_user, {:struct, User}, null: true
    field :posts, {:list, {:struct, Post}}, default: []
    field :selected_post, {:struct, Post}, null: true

    # UI state
    field :loading, :boolean, default: false
    field :error, :string, null: true

    # Nested filter state
    embeds_one :filter do
      field :status, {:enum, [:all, :published, :draft]}, default: :all
      field :author_id, :integer, null: true
      field :search, :string, default: ""
    end

    # Pagination
    embeds_one :pagination do
      field :page, :integer, default: 1
      field :per_page, :integer, default: 20
      field :total_pages, :integer, default: 1
    end
  end
end
```

## Generated Code

For the schema above, LiveSchema generates:

```elixir
# Struct
defstruct [
  :current_user,
  posts: [],
  selected_post: nil,
  loading: false,
  error: nil,
  filter: %Filter{},
  pagination: %Pagination{}
]

# Type spec
@type t :: %__MODULE__{
  current_user: User.t() | nil,
  posts: [Post.t()],
  selected_post: Post.t() | nil,
  loading: boolean(),
  error: String.t() | nil,
  filter: Filter.t(),
  pagination: Pagination.t()
}

# Setters
def set_current_user(state, value)
def set_posts(state, value)
def set_selected_post(state, value)
def set_loading(state, value)
def set_error(state, value)
def set_filter(state, value)
def set_pagination(state, value)

# Constructors
def new()
def new(attrs)
def new!(attrs)

# Introspection
def __live_schema__(:fields)
def __live_schema__({:field, name})
def __live_schema__(:embeds)
def __live_schema__(:reducers)
```
