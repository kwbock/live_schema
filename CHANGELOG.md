# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-10

### Added

- Initial release of LiveSchema
- Schema DSL for defining state structures
  - `field/2,3` macro for field definitions
  - `embeds_one/2` and `embeds_many/2` for nested structures
  - Full type system with primitives and parameterized types
- Auto-generated code
  - Struct definition with defaults
  - Type specifications (`@type t`)
  - Setter functions (`set_*/2`)
  - Constructors (`new/0`, `new/1`, `new!/1`)
  - Introspection (`__live_schema__/1`)
- Action system for state transitions
  - `action/2,3` macro for sync actions
  - `async_action/2,3` for async operations
  - Guard clause support
  - Before/after middleware hooks
- Validation system
  - Runtime type validation (configurable)
  - Built-in validators (format, length, inclusion, etc.)
  - Custom validation functions
  - Rich error messages with hints
- Phoenix integration
  - `LiveSchema.View` for LiveView integration
- Developer experience
  - Custom `Inspect` implementation
  - Telemetry events for observability
  - Mix tasks for code generation and validation
- Testing utilities
  - `LiveSchema.Test` module with assertion helpers
  - Property-based testing support with StreamData
  - State diff utilities
- Comprehensive documentation
  - API documentation with doctests
  - Guides for all major features
  - Migration guide from raw assigns
