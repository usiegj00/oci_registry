require "spec_helper"

RSpec.describe OCIRegistry::Remote do
  describe ".http_get" do
    context "with successful response" do
      it "returns the response" do
        stub_request(:get, "https://example.com/test")
          .to_return(status: 200, body: "success")

        response = described_class.http_get(URI("https://example.com/test"))
        expect(response).to be_a(Net::HTTPSuccess)
        expect(response.body).to eq("success")
      end
    end

    context "with redirect" do
      it "follows redirects" do
        stub_request(:get, "https://example.com/test")
          .to_return(status: 302, headers: { "Location" => "https://example.com/redirected" })
        
        stub_request(:get, "https://example.com/redirected")
          .to_return(status: 200, body: "redirected success")

        response = described_class.http_get(URI("https://example.com/test"))
        expect(response.body).to eq("redirected success")
      end

      it "raises error after too many redirects" do
        stub_request(:get, /example\.com/)
          .to_return(status: 302, headers: { "Location" => "https://example.com/loop" })

        expect {
          described_class.http_get(URI("https://example.com/test"), {}, 0)
        }.to raise_error("Too many HTTP redirects")
      end

      it "strips Authorization header when redirecting to different host" do
        headers = { 'Authorization' => 'Bearer token123' }
        
        stub_request(:get, "https://registry.docker.io/test")
          .with(headers: headers)
          .to_return(status: 302, headers: { 'Location' => 'https://s3.amazonaws.com/bucket/file' })
        
        # Should NOT have Authorization header
        stub_request(:get, "https://s3.amazonaws.com/bucket/file")
          .with { |request| request.headers['Authorization'].nil? }
          .to_return(status: 200, body: "S3 content")

        response = described_class.http_get(URI("https://registry.docker.io/test"), headers)
        expect(response.body).to eq("S3 content")
      end

      it "preserves Authorization header when redirecting to same host" do
        headers = { 'Authorization' => 'Bearer token123' }
        
        stub_request(:get, "https://registry.docker.io/v2/test")
          .with(headers: headers)
          .to_return(status: 302, headers: { 'Location' => 'https://registry.docker.io/v2/test-redirect' })
        
        # Should still have Authorization header
        stub_request(:get, "https://registry.docker.io/v2/test-redirect")
          .with(headers: headers)
          .to_return(status: 200, body: "Registry content")

        response = described_class.http_get(URI("https://registry.docker.io/v2/test"), headers)
        expect(response.body).to eq("Registry content")
      end
    end

    context "with rate limiting" do
      it "retries after rate limit" do
        call_count = 0
        stub_request(:get, "https://example.com/test")
          .to_return do |request|
            call_count += 1
            if call_count == 1
              { status: 429, headers: { "Retry-After" => "0" } }
            else
              { status: 200, body: "success after retry" }
            end
          end

        response = described_class.http_get(URI("https://example.com/test"))
        expect(response.body).to eq("success after retry")
        expect(call_count).to eq(2)
      end
    end
  end

  describe ".get_docker_token" do
    it "returns token from auth endpoint" do
      stub_request(:get, "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nginx:pull")
        .to_return(status: 200, body: { token: "test-token" }.to_json)

      token = described_class.get_docker_token("library/nginx")
      expect(token).to eq("test-token")
    end

    it "includes basic auth when credentials provided" do
      stub_request(:get, "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nginx:pull")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("user:pass")}" })
        .to_return(status: 200, body: { token: "auth-token" }.to_json)

      token = described_class.get_docker_token("library/nginx", "user", "pass")
      expect(token).to eq("auth-token")
    end
  end

  describe ".get_manifest" do
    it "fetches manifest with proper headers" do
      stub_request(:get, "https://registry-1.docker.io/v2/library/nginx/manifests/latest")
        .with(headers: {
          "Authorization" => "Bearer test-token",
          "Accept" => /application\/vnd\.oci\.image/
        })
        .to_return(status: 200, body: { schemaVersion: 2 }.to_json)

      manifest = described_class.get_manifest("registry-1.docker.io", "test-token", "library/nginx", "latest")
      expect(manifest["schemaVersion"]).to eq(2)
    end
  end

  describe ".get_tags" do
    it "fetches tags with pagination" do
      stub_request(:get, "https://registry-1.docker.io/v2/library/nginx/tags/list?n=100")
        .to_return(
          status: 200,
          body: { tags: ["1.0", "1.1"] }.to_json,
          headers: { "Link" => "</v2/library/nginx/tags/list?n=100&last=1.1>; rel=\"next\"" }
        )

      stub_request(:get, "https://registry-1.docker.io/v2/library/nginx/tags/list?n=100&last=1.1")
        .to_return(
          status: 200,
          body: { tags: ["1.2", "latest"] }.to_json
        )

      tags = described_class.get_tags("registry-1.docker.io", "test-token", "library/nginx")
      expect(tags).to eq(["1.0", "1.1", "1.2", "latest"])
    end
  end
end
