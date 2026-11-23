#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ruby scripts/validate.rb

find manifests -type f -name '*.yaml' -print0 | while IFS= read -r -d '' file; do
  while IFS= read -r script; do
    [ -z "$script" ] && continue
    bash -n <(printf '%s\n' "$script")
  done < <(ruby -ryaml -e '
    def walk(value, &block)
      case value
      when Hash
        value.each do |key, child|
          yield child if %w[args command].include?(key.to_s) && child.is_a?(Array)
          walk(child, &block)
        end
      when Array
        value.each { |child| walk(child, &block) }
      end
    end
    YAML.load_stream(File.read(ARGV.fetch(0))).compact.each do |doc|
      walk(doc) do |value|
        value.each { |entry| puts entry if entry.is_a?(String) && entry.include?("set -e") }
      end
    end
  ' "$file")
done

echo "Discourse repository validation passed"
