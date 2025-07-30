require 'uri'

# Define a custom class for Docker URIs
module OCIRegistry
  class URI < URI::Generic
    attr_accessor :repository, :tag, :digest, :host, :scheme

    def initialize(uri)
      raise ArgumentError, 'OCIRegistry::URI->URI cannot be nil' if uri.nil?
      raise ArgumentError, 'OCIRegistry::URI->URI must be a String' unless uri.is_a?(String)

      # TODO: This addition makes this less an OCI URI library and more a CNB Builder Resource Library
      # Handle the case where the URI is just ./eol-buildpack/ which is a local path.
      @repository = uri and @scheme = 'local' and return if uri.start_with?('./')

      # Call the parent class constructor
      @parsed = ::URI.parse(uri)  # Use `::URI` to refer to Ruby's URI class

      # Ensure the scheme is docker
      unless ['docker', 'oci'].include?(@parsed.scheme)
        raise ArgumentError, 'URI must start with (docker|oci)://'
      end

      # Extract repository, tag, and digest from the URI's path
      @scheme = @parsed.scheme
      @host = @parsed.host
      @repository, tag_or_digest = @parsed.path.split('@').first.split(':')
      # Remove any leading slashes from the repository
      @repository = @repository.sub(%r{^/*}, '')
      @digest = @parsed.path.split('@')[1]
      @tag = tag_or_digest unless @digest
    end

    # Allow for 
    # heroku/ruby
    # heroku/ruby:2.7.2
    # heroku/ruby@sha256:1234abcd
    # docker://docker.io/heroku/ruby
    # docker://docker.io/heroku/ruby:2.7.2
    def to_s
      base = ""
      base += "#{@scheme}://"  if @scheme
      base += "#{@host}/"      if @host
      base += "#{@repository}" if @repository
      base += ":#{@tag}"    if @tag
      base += "@#{@digest}" if @digest
      base
    end
  end
end

# Examples of parsing
# uri1 = DockerURI.new('docker://docker.io/heroku/buildpack-dot@sha256:123')
# uri2 = DockerURI.new('docker://docker.io/heroku/buildpack-dot:3.1.2')

# puts "Parsed URI1: Repository=#{uri1.repository}, Tag=#{uri1.tag}, Digest=#{uri1.digest}"
# puts "Parsed URI2: Repository=#{uri2.repository}, Tag=#{uri2.tag}, Digest=#{uri2.digest}"

