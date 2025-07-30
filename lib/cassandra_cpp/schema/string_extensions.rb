# frozen_string_literal: true

# String extensions for schema management
class String
  # Convert CamelCase to snake_case
  def underscore
    gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
      gsub(/([a-z\d])([A-Z])/, '\1_\2').
      tr('-', '_').
      downcase
  end unless method_defined?(:underscore)

  # Convert snake_case to CamelCase
  def camelize
    split('_').map(&:capitalize).join
  end unless method_defined?(:camelize)
end