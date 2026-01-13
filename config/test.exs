import Config

# Test configuration for LiveSchema
# Enable strict validation to catch issues in tests

config :live_schema,
  # Enable runtime type validation
  validate_at: :runtime,
  # Raise on validation errors in tests
  on_error: :raise
