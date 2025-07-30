require "spec_helper"
require "tempfile"
require "json"

RSpec.describe OCIRegistry::Utils do
  describe ".calculate_sha256" do
    it "calculates SHA256 hash of a file" do
      Tempfile.create("test") do |file|
        file.write("test content")
        file.flush
        
        hash = described_class.calculate_sha256(file.path)
        expect(hash).to eq(Digest::SHA256.hexdigest("test content"))
      end
    end
  end

  describe ".write_policy" do
    it "writes a policy file" do
      Tempfile.create(["policy", ".json"]) do |file|
        described_class.write_policy(filename: file.path)
        
        content = JSON.parse(File.read(file.path))
        expect(content["default"]).to be_an(Array)
        expect(content["default"].first["type"]).to eq("insecureAcceptAnything")
      end
    end
  end

  describe ".sum_layers" do
    context "with valid skopeo inspect output" do
      let(:skopeo_inspect) do
        {
          "Digest" => "sha256:abc123",
          "LayersData" => [
            { "Size" => 1000 },
            { "Size" => 2000 },
            { "Size" => 3000 }
          ]
        }
      end

      it "returns the sum of layer sizes" do
        expect(described_class.sum_layers(skopeo_inspect)).to eq(6000)
      end
    end

    context "with string input" do
      let(:skopeo_inspect) do
        {
          "Digest" => "sha256:abc123",
          "LayersData" => [
            { "Size" => 1000 }
          ]
        }.to_json
      end

      it "parses JSON and returns the sum" do
        expect(described_class.sum_layers(skopeo_inspect)).to eq(1000)
      end
    end

    context "with missing LayersData" do
      let(:skopeo_inspect) do
        { "Digest" => "sha256:abc123" }
      end

      it "raises an error" do
        expect { described_class.sum_layers(skopeo_inspect) }.to raise_error("No layers found.")
      end
    end
  end
end
