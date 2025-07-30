# frozen_string_literal: true

require "oci_registry/version"
require "oci_registry/client"
require "oci_registry/remote"
require "oci_registry/uri"
require "oci_registry/utils"

module OCIRegistry
  class Error < StandardError; end
end
