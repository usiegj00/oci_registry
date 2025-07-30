require "spec_helper"

RSpec.describe OCIRegistry do
  it "has a version number" do
    expect(OCIRegistry::VERSION).not_to be nil
  end

  it "defines error class" do
    expect(OCIRegistry::Error).to be < StandardError
  end
end
