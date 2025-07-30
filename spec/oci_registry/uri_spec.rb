require "spec_helper"

RSpec.describe OCIRegistry::URI do
  describe "#initialize" do
    context "with docker URI" do
      let(:uri_string) { "docker://docker.io/library/nginx:latest" }
      let(:uri) { described_class.new(uri_string) }

      it "parses the repository correctly" do
        expect(uri.repository).to eq("library/nginx")
      end

      it "parses the tag correctly" do
        expect(uri.tag).to eq("latest")
      end

      it "parses the host correctly" do
        expect(uri.host).to eq("docker.io")
      end

      it "parses the scheme correctly" do
        expect(uri.scheme).to eq("docker")
      end

      it "converts to string correctly" do
        expect(uri.to_s).to eq(uri_string)
      end
    end

    context "with digest" do
      let(:uri_string) { "docker://gcr.io/project/image@sha256:abc123" }
      let(:uri) { described_class.new(uri_string) }

      it "parses the digest correctly" do
        expect(uri.digest).to eq("sha256:abc123")
      end

      it "does not have a tag when digest is present" do
        expect(uri.tag).to be_nil
      end
    end

    context "with local path" do
      let(:uri_string) { "./eol-buildpack/" }
      let(:uri) { described_class.new(uri_string) }

      it "recognizes local paths" do
        expect(uri.scheme).to eq("local")
        expect(uri.repository).to eq("./eol-buildpack/")
      end
    end

    context "with invalid URI" do
      it "raises error when URI is nil" do
        expect { described_class.new(nil) }.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "raises error when URI is not a string" do
        expect { described_class.new(123) }.to raise_error(ArgumentError, /must be a String/)
      end

      it "raises error when scheme is not docker or oci" do
        expect { described_class.new("http://example.com") }.to raise_error(ArgumentError, /must start with/)
      end
    end
  end
end
