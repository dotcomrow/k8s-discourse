#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
files = Dir[File.join(ROOT, "manifests", "*.yaml")].sort
abort "No manifests found" if files.empty?

identities = {}
documents = []
files.each do |file|
  YAML.load_stream(File.read(file)).compact.each_with_index do |doc, index|
    unless doc.is_a?(Hash) && doc["apiVersion"] && doc["kind"] && doc.dig("metadata", "name")
      abort "Invalid Kubernetes document in #{file} document #{index + 1}"
    end
    namespace = doc.dig("metadata", "namespace") || "_cluster"
    identity = [doc["apiVersion"], doc["kind"], namespace, doc.dig("metadata", "name")]
    abort "Duplicate Kubernetes identity: #{identity.join("/")}" if identities.key?(identity)
    identities[identity] = file
    documents << doc
  end
rescue Psych::SyntaxError => e
  abort "YAML error in #{file}: #{e.message}"
end

source = File.read(File.join(ROOT, "containers", "discourse.yml"))
commit = source[/version:\s*["']?([0-9a-f]{40})/, 1]
abort "Discourse source commit is not pinned" unless commit

rendered = files.map { |file| File.read(file) }.join("\n")
abort "Manifest image does not match pinned Discourse commit" unless rendered.include?("ghcr.io/dotcomrow/discourse:#{commit}")
abort "Oracle SSH tunnel secrets are not reused" unless rendered.include?("directus_db_ssh_private_key_b64")
abort "GraphQL async request contract missing" unless rendered.include?("graphql.async.requests.v1")
abort "GraphQL async response contract missing" unless rendered.include?("graphql.async.responses.v1")
abort "Teleport enrollment missing" unless rendered.include?('teleport.dev/enroll: "true"')
abort "Discourse Redis DB 4 allocation missing" unless rendered.include?('logical_database: 4')
abort "Worker Redis DB 5 allocation missing" unless rendered.include?('logical_database: 5')

%w[
  discourse_db_password
  discourse_secret_key_base
  discourse_admin_password
  discourse_integration_api_key
].each do |secret_name|
  abort "Flat retained secret #{secret_name} is missing" unless rendered.include?("key: #{secret_name}, property: value")
  abort "Vault policy for #{secret_name} is missing" unless rendered.include?("secret/data/#{secret_name}")
end
abort "Nested Discourse Vault secret is forbidden" if rendered.include?('secret/data/discourse"')
abort "Existing GitHub Packages pull credentials are not reused" unless rendered.include?('key: k8s-rules-engine-github-packages-token, property: value')
abort "Discourse image pull secret is not referenced" unless rendered.scan('name: discourse-ghcr').length >= 4

puts "Validated #{documents.length} Kubernetes resources across #{files.length} files"
