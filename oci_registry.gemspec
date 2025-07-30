# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "oci_registry/version"

Gem::Specification.new do |spec|
  spec.name          = "oci_registry"
  spec.version       = OCIRegistry::VERSION
  spec.authors       = ["Jonathan Siegel"]
  spec.email         = ["usiegj00@gmail.com"]

  spec.summary       = "Ruby client for OCI/Docker Registry HTTP API v2"
  spec.description   = "A Ruby library for interacting with OCI/Docker registries using the native HTTP/tar/sha format to navigate repositories and retrieve tags, metadata and other useful information."
  spec.homepage      = "https://github.com/usiegj00/oci_registry"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir["{lib}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "json", ">= 2.0"
  spec.add_dependency "shellwords"
  spec.add_dependency "minitar", "~> 1.0"
  
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.1"
end
