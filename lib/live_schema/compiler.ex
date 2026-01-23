defmodule LiveSchema.Compiler do
  @moduledoc false

  # Handles @before_compile to generate all the code from collected schema attributes.

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :live_schema_fields) |> Enum.reverse()
    embeds = Module.get_attribute(env.module, :live_schema_embeds) |> Enum.reverse()
    actions = Module.get_attribute(env.module, :live_schema_actions) |> Enum.reverse()
    before_hooks = Module.get_attribute(env.module, :live_schema_before_hooks) |> Enum.reverse()
    after_hooks = Module.get_attribute(env.module, :live_schema_after_hooks) |> Enum.reverse()

    # Generate embedded modules first
    embed_modules = generate_embed_modules(embeds, env.module)

    # Build field definitions including embeds
    all_fields = build_all_fields(fields, embeds, env.module)

    # Generate struct definition
    struct_def = generate_struct(all_fields)

    # Generate type spec
    type_spec = generate_type_spec(all_fields, env.module)

    # Generate setters
    setters = generate_setters(all_fields, env.module)

    # Generate constructors
    constructors = generate_constructors(all_fields, env.module)

    # Generate introspection functions
    introspection = generate_introspection(all_fields, embeds, actions, env.module)

    # Generate apply/2 dispatcher
    apply_dispatcher = generate_apply_dispatcher(actions, before_hooks, after_hooks, env.module)

    # Generate Inspect implementation
    inspect_impl = generate_inspect_impl(all_fields, env.module)

    quote do
      unquote_splicing(embed_modules)
      unquote(struct_def)
      unquote(type_spec)
      unquote_splicing(setters)
      unquote_splicing(constructors)
      unquote_splicing(introspection)
      unquote(apply_dispatcher)
      unquote(inspect_impl)
    end
  end

  # Generate nested modules for inline embeds
  defp generate_embed_modules(embeds, parent_module) do
    Enum.flat_map(embeds, fn
      {name, _cardinality, {:inline, block}, _opts} when block != nil ->
        module_name = embed_module_name(parent_module, name)
        [generate_inline_embed_module(module_name, block)]

      _ ->
        []
    end)
  end

  defp embed_module_name(parent, name) do
    suffix = name |> to_string() |> Macro.camelize()
    Module.concat(parent, suffix)
  end

  defp generate_inline_embed_module(module_name, block) do
    quote do
      defmodule unquote(module_name) do
        use LiveSchema

        schema do
          unquote(block)
        end
      end
    end
  end

  # Build complete field list including embeds
  defp build_all_fields(fields, embeds, parent_module) do
    field_list =
      Enum.map(fields, fn {name, type, opts} ->
        nullable = Keyword.get(opts, :null, false)

        # If field is nullable and no explicit default, default to nil
        default =
          case Keyword.fetch(opts, :default) do
            {:ok, value} -> value
            :error -> if nullable, do: nil, else: LiveSchema.Types.default_for_type(type)
          end

        %{
          name: name,
          type: type,
          opts: opts,
          default: default,
          required: Keyword.get(opts, :required, false),
          nullable: nullable,
          setter: Keyword.get(opts, :setter, :"set_#{name}"),
          redact: Keyword.get(opts, :redact, false),
          doc: Keyword.get(opts, :doc),
          validate: Keyword.get(opts, :validate)
        }
      end)

    embed_fields =
      Enum.map(embeds, fn {name, cardinality, source, opts} ->
        module =
          case source do
            {:module, mod} -> mod
            {:inline, _} -> embed_module_name(parent_module, name)
          end

        type =
          case cardinality do
            :one -> {:struct, module}
            :many -> {:list, {:struct, module}}
          end

        # Use nil as struct default; new/0 will initialize embeds
        default =
          case cardinality do
            :one -> nil
            :many -> []
          end

        %{
          name: name,
          type: type,
          opts: opts,
          default: default,
          required: false,
          nullable: Keyword.get(opts, :null, cardinality == :one),
          setter: :"set_#{name}",
          redact: false,
          doc: Keyword.get(opts, :doc),
          validate: nil,
          embed: true,
          embed_module: module,
          embed_cardinality: cardinality
        }
      end)

    field_list ++ embed_fields
  end

  # Generate defstruct
  defp generate_struct(fields) do
    struct_fields =
      Enum.map(fields, fn field ->
        {field.name, Macro.escape(field.default)}
      end)

    quote do
      defstruct unquote(struct_fields)
    end
  end

  # Generate @type t :: %__MODULE__{}
  defp generate_type_spec(fields, _module) do
    field_types =
      Enum.map(fields, fn field ->
        type_ast = LiveSchema.Types.type_to_spec(field.type)

        # Add | nil if field is nullable
        type_ast =
          if field.nullable do
            quote do: unquote(type_ast) | nil
          else
            type_ast
          end

        {field.name, type_ast}
      end)

    quote do
      @type t :: %__MODULE__{unquote_splicing(field_types)}
    end
  end

  # Generate setter functions
  defp generate_setters(fields, module) do
    Enum.flat_map(fields, fn field ->
      case field.setter do
        false ->
          []

        setter_name when is_atom(setter_name) ->
          [generate_setter(field, setter_name, module)]
      end
    end)
  end

  defp generate_setter(field, setter_name, _module) do
    field_name = field.name
    has_validation = field.validate != nil

    if has_validation do
      quote do
        @doc """
        Sets the #{unquote(field_name)} field with validation.
        """
        @spec unquote(setter_name)(t(), any()) :: t()
        def unquote(setter_name)(%__MODULE__{} = state, value) do
          case LiveSchema.Validation.validate_field(
                 unquote(field_name),
                 value,
                 unquote(Macro.escape(field))
               ) do
            :ok ->
              %{state | unquote(field_name) => value}

            {:error, _} = error ->
              LiveSchema.Validation.handle_error(error, __MODULE__, unquote(field_name))
              %{state | unquote(field_name) => value}
          end
        end
      end
    else
      quote do
        @doc """
        Sets the #{unquote(field_name)} field.
        """
        @spec unquote(setter_name)(t(), any()) :: t()
        def unquote(setter_name)(%__MODULE__{} = state, value) do
          %{state | unquote(field_name) => value}
        end
      end
    end
  end

  # Generate new/0, new/1, new!/1
  defp generate_constructors(fields, _module) do
    required_fields = Enum.filter(fields, & &1.required) |> Enum.map(& &1.name)

    # Get embeds that need initialization
    embeds_one =
      fields
      |> Enum.filter(&Map.get(&1, :embed))
      |> Enum.filter(&(&1.embed_cardinality == :one))
      |> Enum.map(fn field -> {field.name, field.embed_module} end)

    new_body =
      if Enum.empty?(embeds_one) do
        quote do: %__MODULE__{}
      else
        # Generate: %__MODULE__{field1: Mod1.new(), field2: Mod2.new(), ...}
        init_pairs =
          Enum.map(embeds_one, fn {name, mod} ->
            {name, quote(do: unquote(mod).new())}
          end)

        quote do: struct!(__MODULE__, unquote(init_pairs))
      end

    [
      quote do
        @doc """
        Creates a new state struct with default values.
        """
        @spec new() :: t()
        def new do
          unquote(new_body)
        end

        @doc """
        Creates a new state struct with the given attributes.

        Attributes are merged over defaults. Nested embeds can be
        provided as maps and will be converted to their struct types.
        """
        @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
        def new(attrs) when is_map(attrs) or is_list(attrs) do
          attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

          base = new()
          result = Enum.reduce(attrs, base, &apply_attr/2)

          case validate_required(result, unquote(required_fields)) do
            :ok -> {:ok, result}
            {:error, _} = error -> error
          end
        end

        @doc """
        Creates a new state struct, raising on validation failure.
        """
        @spec new!(map() | keyword()) :: t()
        def new!(attrs \\ %{}) do
          case new(attrs) do
            {:ok, state} -> state
            {:error, reason} -> raise ArgumentError, "Failed to create state: #{inspect(reason)}"
          end
        end

        defp apply_attr({key, value}, state) when is_atom(key) do
          setter = :"set_#{key}"

          if function_exported?(__MODULE__, setter, 2) do
            apply(__MODULE__, setter, [state, value])
          else
            state
          end
        end

        defp apply_attr({key, value}, state) when is_binary(key) do
          apply_attr({String.to_existing_atom(key), value}, state)
        rescue
          ArgumentError -> state
        end

        defp validate_required(state, required_fields) do
          missing =
            Enum.filter(required_fields, fn field ->
              Map.get(state, field) == nil
            end)

          case missing do
            [] -> :ok
            fields -> {:error, {:missing_required_fields, fields}}
          end
        end
      end
    ]
  end

  # Generate introspection functions
  defp generate_introspection(fields, embeds, actions, _module) do
    field_names = Enum.map(fields, & &1.name)
    embed_names = Enum.map(embeds, &elem(&1, 0))
    action_names = Enum.map(actions, &elem(&1, 0))

    field_info =
      Enum.map(fields, fn field ->
        {field.name,
         %{
           type: field.type,
           default: field.default,
           required: field.required,
           nullable: field.nullable,
           setter: field.setter,
           redact: field.redact,
           doc: field.doc
         }}
      end)

    [
      quote do
        @doc """
        Returns information about the schema.

        ## Keys

        - `:fields` - List of field names
        - `{:field, name}` - Info about a specific field
        - `:embeds` - List of embed names
        - `:actions` - List of action names
        - `:type` - The full type specification

        """
        @spec __live_schema__(atom() | {:field, atom()}) :: any()
        def __live_schema__(:fields), do: unquote(field_names)
        def __live_schema__(:embeds), do: unquote(embed_names)
        def __live_schema__(:actions), do: unquote(action_names)

        def __live_schema__({:field, name}) do
          unquote(Macro.escape(Map.new(field_info)))[name]
        end

        def __live_schema__(:type) do
          quote do
            %unquote(__MODULE__){}
          end
        end
      end
    ]
  end

  # Generate apply/2 dispatcher
  defp generate_apply_dispatcher(actions, before_hooks, after_hooks, module) do
    if Enum.empty?(actions) do
      quote do
        @doc """
        Applies an action to the state using the matching action handler.

        No actions are defined for this schema.
        """
        @spec apply(t(), tuple()) :: t()
        def apply(_state, action) do
          raise LiveSchema.ActionError,
            action: elem(action, 0),
            available_actions: [],
            schema: unquote(module)
        end
      end
    else
      action_names = Enum.map(actions, &elem(&1, 0))

      quote do
        @doc """
        Applies an action to the state using the matching action handler.

        Available actions: #{inspect(unquote(action_names))}
        """
        @spec apply(t(), tuple()) :: t()
        def apply(state, action) do
          action_name = elem(action, 0)

          # Run before hooks
          Enum.each(unquote(before_hooks), fn hook ->
            apply(__MODULE__, hook, [state, action])
          end)

          # Apply the action
          new_state = apply_action(state, action)

          # Run after hooks
          Enum.each(unquote(after_hooks), fn hook ->
            apply(__MODULE__, hook, [state, new_state, action])
          end)

          new_state
        end

        defp apply_action(_state, action) do
          action_name = elem(action, 0)

          raise LiveSchema.ActionError,
            action: action_name,
            available_actions: unquote(action_names),
            schema: unquote(module)
        end
      end
    end
  end

  # Generate Inspect protocol implementation
  defp generate_inspect_impl(fields, module) do
    redacted_fields = fields |> Enum.filter(& &1.redact) |> Enum.map(& &1.name)
    visible_fields = fields |> Enum.reject(& &1.redact) |> Enum.map(& &1.name)

    module_name =
      module
      |> Module.split()
      |> List.last()

    quote do
      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(struct, opts) do
          visible_pairs =
            unquote(visible_fields)
            |> Enum.map(fn field ->
              {field, Map.get(struct, field)}
            end)

          redacted_info =
            case unquote(redacted_fields) do
              [] -> []
              fields -> [{:redacted, fields}]
            end

          all_pairs = visible_pairs ++ redacted_info

          concat([
            "#",
            unquote(module_name),
            "<",
            to_doc(Map.new(all_pairs), opts),
            ">"
          ])
        end
      end
    end
  end
end
