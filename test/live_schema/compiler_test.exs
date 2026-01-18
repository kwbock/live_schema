defmodule LiveSchema.CompilerTest do
  use ExUnit.Case, async: true

  # Test schema with various field options
  defmodule BasicSchema do
    use LiveSchema

    schema do
      field :name, :string, default: "default"
      field :count, :integer, default: 0
      field :active, :boolean, default: false
      field :tags, {:list, :string}, default: []
      field :status, {:enum, [:pending, :done]}, default: :pending
    end
  end

  # Test schema with nullable fields
  defmodule NullableSchema do
    use LiveSchema

    schema do
      field :required_name, :string, default: ""
      field :optional_name, :string, null: true
      field :optional_count, :integer, null: true
      field :optional_with_default, :string, null: true, default: "has_default"
    end
  end

  # Test schema with required fields
  defmodule RequiredFieldsSchema do
    use LiveSchema

    schema do
      field :name, :string, required: true
      field :email, :string, required: true
      field :optional, :string, default: ""
    end
  end

  # Test schema with custom setter options
  defmodule SetterOptionsSchema do
    use LiveSchema

    schema do
      field :normal, :string, default: ""
      field :custom_setter, :string, default: "", setter: :update_custom
      field :no_setter, :string, default: "", setter: false
    end
  end

  # Test schema with redacted fields
  defmodule RedactedSchema do
    use LiveSchema

    schema do
      field :username, :string, default: ""
      field :password, :string, default: "", redact: true
      field :api_key, :string, default: "", redact: true
    end
  end

  # Test schema with validation
  defmodule ValidatedSchema do
    use LiveSchema

    schema do
      field :email, :string, default: "", validate: [format: ~r/@/]
      field :age, :integer, default: 0, validate: [number: [greater_than_or_equal_to: 0]]
    end
  end

  # Test schema with inline embeds
  defmodule InlineEmbedSchema do
    use LiveSchema

    schema do
      field :title, :string, default: ""

      embeds_one :settings do
        field :theme, {:enum, [:light, :dark]}, default: :light
        field :notifications, :boolean, default: true
      end

      embeds_many :items do
        field :name, :string, default: ""
        field :quantity, :integer, default: 1
      end
    end
  end

  # Test schema with reducers
  defmodule ReducerSchema do
    use LiveSchema

    schema do
      field :count, :integer, default: 0
      field :name, :string, default: ""
    end

    reducer :increment do
      set_count(state, state.count + 1)
    end

    reducer :decrement do
      set_count(state, state.count - 1)
    end

    reducer :set_name, [:new_name] do
      set_name(state, new_name)
    end
  end

  # Test empty schema
  defmodule EmptySchema do
    use LiveSchema

    schema do
    end
  end

  describe "struct generation" do
    test "generates struct with correct fields" do
      state = %BasicSchema{}
      assert Map.has_key?(state, :name)
      assert Map.has_key?(state, :count)
      assert Map.has_key?(state, :active)
      assert Map.has_key?(state, :tags)
      assert Map.has_key?(state, :status)
    end

    test "generates struct with correct default values" do
      state = %BasicSchema{}
      assert state.name == "default"
      assert state.count == 0
      assert state.active == false
      assert state.tags == []
      assert state.status == :pending
    end

    test "nullable fields default to nil when no default specified" do
      state = %NullableSchema{}
      assert state.required_name == ""
      assert state.optional_name == nil
      assert state.optional_count == nil
    end

    test "nullable fields can have explicit defaults" do
      state = %NullableSchema{}
      assert state.optional_with_default == "has_default"
    end

    test "empty schema generates valid struct" do
      state = %EmptySchema{}
      assert state.__struct__ == EmptySchema
    end
  end

  describe "constructor new/0" do
    test "creates struct with default values" do
      state = BasicSchema.new()
      assert state.name == "default"
      assert state.count == 0
    end

    test "initializes embeds_one with nested struct" do
      state = InlineEmbedSchema.new()
      assert state.settings != nil
      assert state.settings.__struct__ == InlineEmbedSchema.Settings
      assert state.settings.theme == :light
    end

    test "initializes embeds_many with empty list" do
      state = InlineEmbedSchema.new()
      assert state.items == []
    end
  end

  describe "constructor new/1" do
    test "creates struct with provided values" do
      {:ok, state} = BasicSchema.new(name: "test", count: 42)
      assert state.name == "test"
      assert state.count == 42
    end

    test "accepts keyword list" do
      {:ok, state} = BasicSchema.new(name: "keyword", count: 10)
      assert state.name == "keyword"
      assert state.count == 10
    end

    test "accepts map with atom keys" do
      {:ok, state} = BasicSchema.new(%{name: "map", count: 20})
      assert state.name == "map"
      assert state.count == 20
    end

    test "accepts map with string keys" do
      {:ok, state} = BasicSchema.new(%{"name" => "string_key", "count" => 30})
      assert state.name == "string_key"
      assert state.count == 30
    end

    test "ignores unknown fields" do
      {:ok, state} = BasicSchema.new(name: "test", unknown_field: "ignored")
      assert state.name == "test"
      refute Map.has_key?(state, :unknown_field)
    end

    test "returns error when required fields are missing" do
      assert {:error, {:missing_required_fields, [:name, :email]}} =
               RequiredFieldsSchema.new(optional: "value")
    end

    test "succeeds when required fields are provided" do
      {:ok, state} = RequiredFieldsSchema.new(name: "test", email: "test@example.com")
      assert state.name == "test"
      assert state.email == "test@example.com"
    end
  end

  describe "constructor new!/1" do
    test "returns struct directly on success" do
      state = BasicSchema.new!(name: "bang")
      assert state.name == "bang"
    end

    test "raises ArgumentError on failure" do
      assert_raise ArgumentError, ~r/Failed to create state/, fn ->
        RequiredFieldsSchema.new!(optional: "only")
      end
    end

    test "works with no arguments" do
      state = BasicSchema.new!()
      assert state.name == "default"
    end
  end

  describe "setter generation" do
    test "generates default setters" do
      state = BasicSchema.new!()
      state = BasicSchema.set_name(state, "updated")
      assert state.name == "updated"
    end

    test "generates setter for all types" do
      state = BasicSchema.new!()
      state = BasicSchema.set_count(state, 100)
      state = BasicSchema.set_active(state, true)
      state = BasicSchema.set_tags(state, ["a", "b"])
      state = BasicSchema.set_status(state, :done)

      assert state.count == 100
      assert state.active == true
      assert state.tags == ["a", "b"]
      assert state.status == :done
    end

    test "generates custom-named setter" do
      state = SetterOptionsSchema.new!()
      state = SetterOptionsSchema.update_custom(state, "custom_value")
      assert state.custom_setter == "custom_value"
    end

    test "does not generate setter when setter: false" do
      refute function_exported?(SetterOptionsSchema, :set_no_setter, 2)
    end

    test "still generates default setter for normal field" do
      assert function_exported?(SetterOptionsSchema, :set_normal, 2)
    end

    test "setters work with embed fields" do
      state = InlineEmbedSchema.new!()
      new_settings = InlineEmbedSchema.Settings.new!(theme: :dark)
      state = InlineEmbedSchema.set_settings(state, new_settings)
      assert state.settings.theme == :dark
    end
  end

  describe "setter with validation" do
    setup do
      original = Application.get_env(:live_schema, :on_error)
      on_exit(fn -> Application.put_env(:live_schema, :on_error, original) end)
      :ok
    end

    test "setter calls validation when field has validators" do
      Application.put_env(:live_schema, :on_error, :raise)

      state = ValidatedSchema.new!()

      # Valid value should work
      state = ValidatedSchema.set_email(state, "valid@email.com")
      assert state.email == "valid@email.com"
    end

    test "setter handles validation error based on config" do
      Application.put_env(:live_schema, :on_error, :ignore)

      state = ValidatedSchema.new!()
      # Invalid value - should still set but validation runs
      state = ValidatedSchema.set_email(state, "invalid")
      assert state.email == "invalid"
    end
  end

  describe "introspection __live_schema__/1" do
    test "returns list of field names" do
      fields = BasicSchema.__live_schema__(:fields)
      assert :name in fields
      assert :count in fields
      assert :active in fields
      assert :tags in fields
      assert :status in fields
    end

    test "returns field info for specific field" do
      info = BasicSchema.__live_schema__({:field, :name})
      assert info.type == :string
      assert info.default == "default"
      assert info.nullable == false
      assert info.required == false
    end

    test "returns nullable info correctly" do
      info = NullableSchema.__live_schema__({:field, :optional_name})
      assert info.nullable == true

      info = NullableSchema.__live_schema__({:field, :required_name})
      assert info.nullable == false
    end

    test "returns required info correctly" do
      info = RequiredFieldsSchema.__live_schema__({:field, :name})
      assert info.required == true

      info = RequiredFieldsSchema.__live_schema__({:field, :optional})
      assert info.required == false
    end

    test "returns redact info correctly" do
      info = RedactedSchema.__live_schema__({:field, :password})
      assert info.redact == true

      info = RedactedSchema.__live_schema__({:field, :username})
      assert info.redact == false
    end

    test "returns custom setter name" do
      info = SetterOptionsSchema.__live_schema__({:field, :custom_setter})
      assert info.setter == :update_custom
    end

    test "returns false for disabled setter" do
      info = SetterOptionsSchema.__live_schema__({:field, :no_setter})
      assert info.setter == false
    end

    test "returns list of embed names" do
      embeds = InlineEmbedSchema.__live_schema__(:embeds)
      assert :settings in embeds
      assert :items in embeds
    end

    test "returns list of reducer names" do
      reducers = ReducerSchema.__live_schema__(:reducers)
      assert :increment in reducers
      assert :decrement in reducers
      assert :set_name in reducers
    end

    test "returns empty list for schema without reducers" do
      reducers = BasicSchema.__live_schema__(:reducers)
      assert reducers == []
    end
  end

  describe "inline embed module generation" do
    test "generates nested module for embeds_one" do
      assert Code.ensure_loaded?(InlineEmbedSchema.Settings)
    end

    test "generates nested module for embeds_many" do
      assert Code.ensure_loaded?(InlineEmbedSchema.Items)
    end

    test "nested module has correct fields" do
      settings = InlineEmbedSchema.Settings.new!()
      assert Map.has_key?(settings, :theme)
      assert Map.has_key?(settings, :notifications)
    end

    test "nested module has correct defaults" do
      settings = InlineEmbedSchema.Settings.new!()
      assert settings.theme == :light
      assert settings.notifications == true
    end

    test "nested module has setters" do
      settings = InlineEmbedSchema.Settings.new!()
      settings = InlineEmbedSchema.Settings.set_theme(settings, :dark)
      assert settings.theme == :dark
    end
  end

  describe "apply dispatcher" do
    test "routes to correct reducer" do
      state = ReducerSchema.new!()
      state = ReducerSchema.apply(state, {:increment})
      assert state.count == 1

      state = ReducerSchema.apply(state, {:decrement})
      assert state.count == 0
    end

    test "passes arguments to reducer" do
      state = ReducerSchema.new!()
      state = ReducerSchema.apply(state, {:set_name, "new_name"})
      assert state.name == "new_name"
    end

    test "raises ActionError for unknown action" do
      state = ReducerSchema.new!()

      assert_raise LiveSchema.ActionError, fn ->
        ReducerSchema.apply(state, {:unknown_action})
      end
    end

    test "raises ActionError for schema without reducers" do
      state = BasicSchema.new!()

      assert_raise LiveSchema.ActionError, fn ->
        BasicSchema.apply(state, {:any_action})
      end
    end
  end

  describe "Inspect implementation" do
    test "shows visible fields" do
      state = RedactedSchema.new!(username: "testuser")
      output = inspect(state)

      assert output =~ "username"
      assert output =~ "testuser"
    end

    test "hides redacted field values" do
      state = RedactedSchema.new!(username: "testuser", password: "secret123", api_key: "key123")
      output = inspect(state)

      refute output =~ "secret123"
      refute output =~ "key123"
      assert output =~ "redacted"
    end

    test "shows which fields are redacted" do
      state = RedactedSchema.new!(password: "secret")
      output = inspect(state)

      assert output =~ ":password"
      assert output =~ ":api_key"
    end
  end

  describe "field type handling" do
    test "handles enum type with correct default" do
      state = BasicSchema.new!()
      assert state.status == :pending
    end

    test "handles list type with empty default" do
      state = BasicSchema.new!()
      assert state.tags == []
    end

    test "handles struct type in embeds" do
      info = InlineEmbedSchema.__live_schema__({:field, :settings})
      assert {:struct, InlineEmbedSchema.Settings} = info.type
    end

    test "handles list of structs in embeds_many" do
      info = InlineEmbedSchema.__live_schema__({:field, :items})
      assert {:list, {:struct, InlineEmbedSchema.Items}} = info.type
    end
  end

  describe "edge cases" do
    test "field with doc option stores documentation" do
      defmodule DocSchema do
        use LiveSchema

        schema do
          field :documented, :string, default: "", doc: "This field has docs"
        end
      end

      info = DocSchema.__live_schema__({:field, :documented})
      assert info.doc == "This field has docs"
    end

    test "multiple schemas can coexist" do
      state1 = BasicSchema.new!()
      state2 = NullableSchema.new!()

      assert state1.__struct__ == BasicSchema
      assert state2.__struct__ == NullableSchema
    end

    test "struct pattern matching works" do
      state = BasicSchema.new!()

      assert %BasicSchema{name: name} = state
      assert name == "default"
    end

    test "can update struct with map syntax" do
      state = BasicSchema.new!()
      updated = %{state | name: "direct_update"}
      assert updated.name == "direct_update"
    end
  end
end
