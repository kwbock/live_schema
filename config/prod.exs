import Config

# Production configuration for LiveSchema
# Disable runtime validation for performance

config :live_schema,
  # Disable runtime validation in production
  validate_at: :none,
  # Ignored when validate_at is :none
  on_error: :ignore
