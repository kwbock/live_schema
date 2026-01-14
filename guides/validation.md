# Validation Guide

LiveSchema provides runtime type validation to catch errors early in development.

## Enabling Validation

Configure validation in your `config/dev.exs`:

```elixir
config :live_schema,
  validate_at: :runtime,  # :runtime | :none
  on_error: :log          # :log | :raise | :ignore
```

Recommended settings:
- **Development**: `validate_at: :runtime, on_error: :log`
- **Test**: `validate_at: :runtime, on_error: :raise`
- **Production**: `validate_at: :none` (for performance)

## Type Validation

All field types are validated at runtime when enabled:

```elixir
schema do
  field :count, :integer, default: 0
  field :status, {:enum, [:pending, :active, :done]}
end

# This will trigger a validation warning/error
state = MyState.new!()
MyState.set_count(state, "not an integer")
# ** (LiveSchema.TypeError) Type mismatch for field :count
#     Expected: integer
#     Got: "not an integer" (string)
```

## Custom Validators

### Built-in Validators

```elixir
schema do
  # Format validation (regex)
  field :email, :string, validate: [
    format: ~r/^[^\s]+@[^\s]+$/
  ]

  # Length validation
  field :username, :string, validate: [
    length: [min: 3, max: 20]
  ]

  # Inclusion/exclusion
  field :role, :atom, validate: [
    inclusion: [:admin, :user, :guest]
  ]

  # Number validation
  field :age, :integer, validate: [
    number: [
      greater_than_or_equal_to: 0,
      less_than: 150
    ]
  ]

  # Multiple validators
  field :password, :string, validate: [
    length: [min: 8],
    format: ~r/[A-Z]/,       # at least one uppercase
    format: ~r/[a-z]/,       # at least one lowercase
    format: ~r/[0-9]/        # at least one digit
  ]
end
```

### Custom Functions

```elixir
schema do
  field :email, :string, validate: &valid_email?/1
end

defp valid_email?(email) do
  case EmailValidator.validate(email) do
    :ok -> true
    {:error, reason} -> {:error, reason}
  end
end
```

### Combining Validators

```elixir
field :username, :string, validate: [
  length: [min: 3, max: 20],
  format: ~r/^[a-z0-9_]+$/,
  custom: &check_availability/1
]
```

## Validation Errors

Validation errors contain detailed information:

```elixir
%LiveSchema.ValidationError{
  field: :email,
  value: "invalid",
  errors: [
    {:format, "must match pattern ~r/@/"},
    {:length, "must be at least 5 characters"}
  ],
  path: [:user, :email]  # For nested fields
}
```

### Formatting Errors

```elixir
# Human-readable format
error |> LiveSchema.ValidationError.format()

# JSON-serializable format (for API responses)
error |> LiveSchema.ValidationError.to_json()
# %{
#   field: :email,
#   path: [:user, :email],
#   errors: [
#     %{type: :format, message: "must match pattern ~r/@/"}
#   ]
# }
```

## Performance Considerations

Runtime validation adds overhead. For production:

```elixir
# config/prod.exs
config :live_schema,
  validate_at: :none
```

Or validate only specific operations:

```elixir
def set_email(state, email) do
  if LiveSchema.Validation.validation_enabled?() do
    # Full validation
    case validate_email(email) do
      :ok -> %{state | email: email}
      {:error, _} = error -> handle_error(error)
    end
  else
    # Skip validation in production
    %{state | email: email}
  end
end
```
