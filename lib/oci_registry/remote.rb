require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'base64'
require 'zlib'
require 'minitar'
require 'stringio'
require 'fileutils'


module OCIRegistry
  class Remote

    # Helper method to handle HTTP GET requests with redirect support
    def self.http_get(uri, headers = {}, limit = 10)
      raise 'Too many HTTP redirects' if limit == 0

      request = Net::HTTP::Get.new(uri)
      headers.each { |k, v| request[k] = v }

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      case response
      when Net::HTTPRedirection
        location = response['location']
        # warn "Redirected to #{location}"
        # Handle the case where location is a relative URL by reconstructing the full URL
        new_uri = ::URI.join(uri, location)
        
        # Don't forward Authorization header across domain boundaries
        # This was discovered through pain and suffering when Docker redirects to S3.
        new_headers = headers.dup
        if uri.host != new_uri.host
          new_headers.delete('Authorization')
        end
        
        http_get(new_uri, new_headers, limit - 1)
      # 429
      when Net::HTTPTooManyRequests
        puts "Rate limited: #{response.code} #{response.message}"
        # Retry after the specified time
        retry_after = response['Retry-After'].to_i || 10
        sleep(retry_after)
        http_get(uri, headers, limit - 1)
      else
        response
      end
    end

    # Step 1: Obtain an Access Token
    def self.get_docker_token(repository, username = nil, password = nil)
      uri = URI("https://auth.docker.io/token?service=registry.docker.io&scope=repository:#{repository}:pull")

      headers = {}
      if username && password
        encoded_credentials = Base64.strict_encode64("#{username}:#{password}")
        headers['Authorization'] = "Basic #{encoded_credentials}"
      end

      response = http_get(uri, headers)

      if response.is_a?(Net::HTTPSuccess)
        json = JSON.parse(response.body)
        json['token']
      else
        error_detail = response.body.to_s.strip
        error_detail = ": #{error_detail}" unless error_detail.empty?
        raise "Failed to obtain token: #{response.code} #{response.message}#{error_detail}"
      end
    end

    # Step 2: Fetch the Image Manifest
    def self.get_manifest(host, token, repository, tag)
      uri = URI("https://#{host}/v2/#{repository}/manifests/#{tag}")
      headers = {
        'Authorization' => "Bearer #{token}",
        'Accept' => [
                      'application/vnd.oci.image.index.v1+json',
                      'application/vnd.docker.distribution.manifest.list.v2+json',
                      'application/vnd.oci.image.manifest.v1+json',
                      'application/vnd.docker.distribution.manifest.v2+json'
        ].join(', ')
      }

      response = http_get(uri, headers)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        error_detail = response.body.to_s.strip
        error_detail = ": #{error_detail}" unless error_detail.empty?
        raise "Failed to fetch manifest: #{response.code} #{response.message}#{error_detail}"
      end
    end

    # Step 4: Retrieve the Image Configuration
    def self.get_blob(host, token, repository, blob_digest)
      uri = URI("https://#{host}/v2/#{repository}/blobs/#{blob_digest}")
      headers = { 'Authorization' => "Bearer #{token}" }

      response = http_get(uri, headers)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        error_detail = response.body.to_s.strip
        error_detail = ": #{error_detail}" unless error_detail.empty?
        raise "Failed to retrieve image configuration for #{uri.inspect}: #{response.code} #{response.message}#{error_detail}"
      end
    end

    # Function to fetch the list of tags for the repository
    def self.get_tags(host, token, repository)
      tags = []
      batch_size = 100
      next_url = "/v2/#{repository}/tags/list?n=#{batch_size}"
      headers = {
        'Authorization' => "Bearer #{token}",
        'Accept' => 'application/json'
      }

      loop do
        uri = URI("https://#{host}#{next_url}")
        response = http_get(uri, headers)

        if response.is_a?(Net::HTTPSuccess)
          json = JSON.parse(response.body)
          tags.concat(json['tags'] || [])

          # Check for pagination
          link_header = response['Link']
          if link_header && link_header.include?('rel="next"')
            next_url = link_header.match(/<(.+)>;/)[1]
          else
            break
          end
        else
          error_detail = response.body.to_s.strip
          error_detail = ": #{error_detail}" unless error_detail.empty?
          puts "Failed to fetch tags for #{repository}: https://#{host}#{next_url} #{response.code} #{response.message}#{error_detail}"
          break
        end
      end

      tags
    end

    # Step 5: Extract Labels and Metadata
    def self.display_metadata(config_json)
      labels = config_json['config']['Labels']
      puts "Labels:"
      puts JSON.pretty_generate(labels)

      puts "\nOther Metadata:"
      metadata = config_json['config']
      puts JSON.pretty_generate(metadata)
    end

    # Function to download and extract layers
    def self.download_and_extract_layers(host, token, repository, layers, file_name)
      layers.each_with_index do |layer, index|
        digest = layer['digest']
        puts "Processing layer #{index + 1}/#{layers.size}: #{digest}"

        # Download the layer blob
        uri = URI("https://#{host}/v2/#{repository}/blobs/#{digest}")
        headers = { 'Authorization' => "Bearer #{token}" }

        response = http_get(uri, headers)

        if response.is_a?(Net::HTTPSuccess)
          # Decompress and extract the tar.gz layer
          found = extract_layer(response.body, file_name)
          return true if found
        else
          error_detail = response.body.to_s.strip
          error_detail = ": #{error_detail}" unless error_detail.empty?
          puts "Failed to download layer #{digest}: #{response.code} #{response.message}#{error_detail}"
        end
      end
      false
    end

    # Function to extract a layer and search for the specified file
    def self.extract_layer(layer_data, file_name)
      # Decompress the gzip layer data
      gz = Zlib::GzipReader.new(StringIO.new(layer_data))
      tar_io = StringIO.new(gz.read)

      # Extract tar contents
      Minitar::Input.open(tar_io) do |tar|
        tar.each do |entry|
          # Normalize file paths to handle different directory structures
          entry_path = entry.full_name.sub(/^\.\//, '').sub(/^\/+/, '')

          if File.basename(entry_path) == file_name
            puts "\nFound '#{file_name}' in layer:"
            contents = entry.read
            puts contents
            return true
          end
        end
      end
      false
    end

  end
end
