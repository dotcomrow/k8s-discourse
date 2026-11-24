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
deployed_images = rendered.scan(%r{image:\s*(ghcr\.io/dotcomrow/discourse:[^\s]+)}).flatten
abort "Discourse deployment images are missing" if deployed_images.empty?
abort "Discourse deployments must use the latest image" unless deployed_images.all? { |image| image == "ghcr.io/dotcomrow/discourse:latest" }
abort "Every Discourse deployment must pull latest" unless rendered.scan("imagePullPolicy: Always").length >= deployed_images.length
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
abort "PostgreSQL vector extension bootstrap is missing" unless rendered.include?('CREATE EXTENSION IF NOT EXISTS vector;')
abort "Discourse must generate HTTPS URLs behind Teleport" unless rendered.include?('DISCOURSE_FORCE_HTTPS, value: "true"')
abort "Discourse local password login must be disabled" unless rendered.include?('DISCOURSE_ENABLE_LOCAL_LOGINS, value: "false"')
abort "Discourse email-link login must be disabled" unless rendered.include?('DISCOURSE_ENABLE_LOCAL_LOGINS_VIA_EMAIL, value: "false"')
abort "Discourse email-code login must be disabled" unless rendered.include?('DISCOURSE_ENABLE_LOCAL_LOGINS_VIA_CODE, value: "false"')
abort "Discourse OIDC is not enabled" unless rendered.include?('DISCOURSE_OPENID_CONNECT_ENABLED')
abort "Discourse OIDC must use the internal Keycloak realm" unless rendered.include?('https://auth.suncoast.systems/realms/internal/.well-known/openid-configuration')
abort "Discourse OIDC must use public-client PKCE" unless rendered.include?('DISCOURSE_OPENID_CONNECT_USE_PKCE')
abort "Discourse OIDC membership claim is missing" unless rendered.include?('DISCOURSE_OPENID_CONNECT_GROUPS_CLAIM, value: suncoast_roles')
abort "Discourse administrator group reconciliation is missing" unless rendered.include?('oidc_admin_group_name = "k8s_discourse_admins"')

image_config = File.read(File.join(ROOT, "containers", "discourse.yml"))
abort "Discourse image baseline must force HTTPS" unless image_config.include?('DISCOURSE_FORCE_HTTPS: "true"')
abort "Discourse image baseline must disable local password login" unless image_config.include?('DISCOURSE_ENABLE_LOCAL_LOGINS: "false"')
abort "Discourse image baseline must disable email-link login" unless image_config.include?('DISCOURSE_ENABLE_LOCAL_LOGINS_VIA_EMAIL: "false"')
abort "Discourse image baseline must disable email-code login" unless image_config.include?('DISCOURSE_ENABLE_LOCAL_LOGINS_VIA_CODE: "false"')
abort "Suncoast OIDC administrator sync plugin is missing" unless image_config.include?('ADMIN_ROLE = "k8s_discourse_admins"')
abort "Suncoast OIDC administrator revocation is missing" unless image_config.include?("user.revoke_admin!")

puts "Validated #{documents.length} Kubernetes resources across #{files.length} files"
