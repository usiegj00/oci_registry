require "spec_helper"

RSpec.describe OCIRegistry::Client do
  let(:client) { described_class.new(username: "test", password: "test") }

  describe "#initialize" do
    it "sets default host" do
      expect(client.host).to eq("registry-1.docker.io")
    end

    it "accepts custom host" do
      custom_client = described_class.new(host: "gcr.io")
      expect(custom_client.host).to eq("gcr.io")
    end

    it "accepts token" do
      token_client = described_class.new(token: "test-token")
      expect(token_client.instance_variable_get(:@token)).to eq("test-token")
    end
  end

  describe "#token" do
    context "with pre-set token" do
      let(:client) { described_class.new(token: "preset-token") }

      it "returns the preset token" do
        expect(client.token("repo")).to eq("preset-token")
      end
    end

    context "without preset token" do
      it "fetches token from registry", vcr: { cassette_name: "docker_token" } do
        allow(OCIRegistry::Remote).to receive(:get_docker_token).and_return("fetched-token")
        
        token = client.token("library/nginx")
        expect(token).to eq("fetched-token")
      end
    end
  end

  describe "#metadata" do
    let(:manifest) do
      {
        "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
        "config" => {
          "digest" => "sha256:config123"
        }
      }
    end

    let(:blob_data) do
      {
        "architecture" => "amd64",
        "os" => "linux"
      }
    end

    before do
      allow(client).to receive(:manifest).and_return(manifest)
      allow(client).to receive(:token).and_return("test-token")
      allow(OCIRegistry::Remote).to receive(:get_blob).and_return(blob_data)
    end

    it "returns metadata for standard manifest" do
      metadata = client.metadata("library/nginx", "latest")
      expect(metadata).to eq(blob_data)
    end

    context "with multi-arch manifest list" do
      let(:multi_arch_manifest) do
        {
          "mediaType" => "application/vnd.docker.distribution.manifest.list.v2+json",
          "manifests" => [
            {
              "platform" => { "architecture" => "arm64", "os" => "linux" },
              "digest" => "sha256:arm64"
            },
            {
              "platform" => { "architecture" => "amd64", "os" => "linux" },
              "digest" => "sha256:amd64"
            }
          ]
        }
      end

      let(:amd64_manifest) do
        {
          "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
          "config" => {
            "digest" => "sha256:config123"
          }
        }
      end

      it "selects amd64 linux manifest" do
        expect(client).to receive(:manifest).with("library/nginx", "latest").and_return(multi_arch_manifest)
        expect(client).to receive(:manifest).with("library/nginx", "sha256:amd64").and_return(amd64_manifest)
        expect(OCIRegistry::Remote).to receive(:get_blob).and_return(blob_data)
        
        metadata = client.metadata("library/nginx", "latest")
        expect(metadata).to eq(blob_data)
      end
    end
  end
  describe "#tags" do
    let(:tags_response) { ["latest", "1.21", "1.21-alpine"] }

    before do
      allow(client).to receive(:token).and_return("test-token")
      allow(OCIRegistry::Remote).to receive(:get_tags).and_return(tags_response)
    end

    it "returns tags array" do
      tags = client.tags("library/nginx")
      expect(tags).to eq(tags_response)
    end

    it "yields tags when block given" do
      yielded_tags = []
      client.tags("library/nginx") { |tag| yielded_tags << tag }
      expect(yielded_tags).to eq(tags_response)
    end
  end
end
