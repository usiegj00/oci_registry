module OCIRegistry
  class Client
    attr_accessor :username, :password, :token, :host
    def initialize(username: nil, password: nil, token: nil, host: 'registry-1.docker.io')
      # Main Execution Flow
      @username  = username
      @password  = password
      @token     = token # e.g. gcloud auth print-access-token
      @tokens    = {}
      @manifests = {}
      @host      = host
    end
    def metadata(repository, tag)
      manifest            = self.manifest(repository, tag)
      case manifest['mediaType']
      when "application/vnd.docker.distribution.manifest.list.v2+json"
        # Multi-arch images have a manifest list
        manifest = manifest['manifests'].find { |m| m['platform']['architecture'] == 'amd64' && m['platform']['os'] == 'linux' }
        self.metadata(repository, manifest['digest'])
      when "application/vnd.docker.distribution.manifest.v2+json"
        # Builders
        blob_digest = manifest['config']['digest']
        OCIRegistry::Remote.get_blob(host, self.token(repository), repository, blob_digest)
      when "application/vnd.oci.image.index.v1+json"
        # Buildpacks give a collection of manifests as an index if they are multi-arch:
        manifest = manifest['manifests'].find { |s| s['platform']['architecture'] == 'amd64' && s['platform']['os'] == 'linux' }
        self.metadata(repository, manifest['digest'])
      when "application/vnd.oci.image.manifest.v1+json"
        # OCI Images
        blob_digest = manifest['config']['digest']
        OCIRegistry::Remote.get_blob(host, self.token(repository), repository, blob_digest)
      else
        raise "Unknown manifest type: #{manifest['mediaType']}"
      end
    end
    def token(repository)
      return @token if @token # e.g. Google Container Registry
      @tokens[repository] = OCIRegistry::Remote.get_docker_token(repository, @username, @password)
    end
    def manifest(repository, tag)
      slug = "#{repository}:#{tag}"
      @manifests[slug]    = OCIRegistry::Remote.get_manifest(self.host, self.token(repository), repository, tag)
    end
    def tags(repository, &block)
      tags = OCIRegistry::Remote.get_tags(self.host, self.token(repository), repository)
      return tags.each(&block) if block_given?
      tags
    end
    def download_and_extract_layers(repository, layers, file_name)
      OCIRegistry::Remote.download_and_extract_layers(host, self.token(repository), repository, layers, file_name)
    end
    def ping
      # ping the api
      OCIRegistry::Remote.http_get(URI("https://#{host}/v2/"), { 'Authorization' => "Bearer #{@token}" })
    end
  end
end
