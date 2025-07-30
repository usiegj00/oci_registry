# OCI Registry

A Ruby library for interacting with OCI/Docker registries using the native HTTP/tar/sha format to navigate repositories and retrieve tags, metadata and other useful information.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'oci_registry'
```

And then execute:

    $ bundle

## Usage

### Client

```ruby
# Create a client for Docker Hub
client = OCIRegistry::Client.new(username: 'user', password: 'pass')

# Create a client for Google Container Registry
client = OCIRegistry::Client.new(token: 'access-token', host: 'gcr.io')

# Get image metadata
metadata = client.metadata('library/nginx', 'latest')

# List tags
client.tags('library/nginx') do |tag|
  puts tag
end

# Get manifest
manifest = client.manifest('library/nginx', 'latest')

# Download and extract layers
layers = manifest['layers']
client.download_and_extract_layers('library/nginx', layers, 'config.json')
```

### URI Parser

```ruby
# Parse Docker/OCI URIs
uri = OCIRegistry::URI.new('docker://docker.io/library/nginx:latest')
puts uri.repository # => "library/nginx"
puts uri.tag        # => "latest"
puts uri.host       # => "docker.io"
```

### Utils

```ruby
# Write skopeo policy file
OCIRegistry::Utils.write_policy(filename: "policy.json")

# Calculate SHA256 of a file
sha = OCIRegistry::Utils.calculate_sha256("/path/to/file")

# Sum layers from skopeo inspect output
size = OCIRegistry::Utils.sum_layers(skopeo_inspect_json)

# Copy image between registries
digest = OCIRegistry::Utils.copy_image(
  src_user: "user1", src_pass: "pass1",
  dst_user: "user2", dst_pass: "pass2",
  src_oci: "docker.io/library/nginx",
  src_commit: "latest",
  dst_oci: "my-registry.com/nginx",
  dst_commit: "latest"
)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

## Contributing

Bug reports and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
