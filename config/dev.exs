import Config

# Development configuration for LiveSchema
# Enable runtime validation with logging for better debugging

config :live_schema,
  # Enable runtime type validation
  validate_at: :runtime,
  # Log validation errors instead of raising
  on_error: :log
