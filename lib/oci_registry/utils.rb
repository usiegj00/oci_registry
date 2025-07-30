# OCI related functions. Generally using skopeo and umoci. These span U9s (Heroku slug repackaging) and 
# Qack (CNB "pack" rebuilding).
# Resources:
# - [Manual OCI building](https://ravichaganti.com/blog/2022-11-28-building-container-images-using-no-tools/)
require 'shellwords'
require 'open3'
require 'json'
require 'digest'
require 'tmpdir'

module OCIRegistry
  class Utils
    # Helper method to run shell commands
    def self.run_command(cmd)
      stdout, stderr, status = Open3.capture3(cmd)
      {
        out: stdout,
        err: stderr,
        status: status.exitstatus
      }
    end

    def self.get_image_digest(image_name)
    end
    
    # Function to calculate SHA256 hash of a file
    def self.calculate_sha256(file_path)
      Digest::SHA256.file(file_path).hexdigest
    end
    
    def self.write_policy(filename: "policy.json")
      File.open(filename, "w") do |f|
        f.write <<~EOF
          {
              "default": [
                  {
                      "type": "insecureAcceptAnything"
                  }
              ],
              "transports":
                  {
                      "docker-daemon":
                          {
                              "": [{"type":"insecureAcceptAnything"}]
                          }
                  }
          }
        EOF
      end
    end
    
    # Takes the output of skopeo inspect and returns the size of the image by adding its layers.
    # cmd = %Q[skopeo inspect oci:#{td}/tmp_stack:latest]
    # skopeo_inspect = JSON.parse(`#{cmd}`)
    def self.sum_layers(skopeo_inspect)
      # Ensure we treat as JSON...
      skopeo_inspect = JSON.parse(skopeo_inspect) if skopeo_inspect.is_a?(String)
      checksum = skopeo_inspect['Digest']
      if skopeo_inspect['LayersData'].nil?
        puts "skopeo_inspect: #{skopeo_inspect.to_yaml}"
        raise "No layers found."
      end
      size = skopeo_inspect['LayersData'].map { |l| l['Size'] }.sum
    end
    
    def self.copy_image(src_user:, src_pass:, dst_user:, dst_pass:, src_oci:, src_commit:, dst_oci:, dst_commit:)
      src_user = Shellwords.escape(src_user)
      src_pass = Shellwords.escape(src_pass)
      dst_user = Shellwords.escape(dst_user)
      dst_pass = Shellwords.escape(dst_pass)

      copy(src_user: src_user, src_pass: src_pass, dst_user: dst_user, dst_pass: dst_pass, src_oci: src_oci, src_commit: src_commit, dst_oci: dst_oci, dst_commit: dst_commit)
      cmd = %Q[skopeo inspect --creds #{dst_user}:#{dst_pass} docker://#{dst_oci}:#{dst_commit}]
      details = run_command(cmd)
      if details[:status] == 1
        # Error occured
        # Logger: ("Error inspecting image:\n#{details[:err]}")
        raise "Image not found in registry #{details[:err]}."
      end
      inspect = JSON.parse(details[:out])
      inspect['Digest']
    end

    # TODO: Copy FROM registry->local then local->registry. This avoids an error where a slow vs fast registry 
    # [causes a timeout](https://github.com/containers/image/issues/1083).
    def self.copy(src_user:, src_pass:, dst_user:, dst_pass:, src_oci:, src_commit:, dst_oci:, dst_commit:)
      retries = 0
      begin
        details = {}
        # We need a tempdir to write the policy file
        Dir.mktmpdir do |dir|
          OCIRegistry::Utils.write_policy(filename: File.join(dir, "policy.json"))
          cmd = %Q[skopeo  --policy #{dir}/policy.json copy --src-creds #{src_user}:#{src_pass} --dest-creds #{dst_user}:#{dst_pass} docker://#{src_oci}:#{src_commit} docker://#{dst_oci}:#{dst_commit}]
          details = run_command(cmd)
          # Dir.mktmpdir do |tar|
          #   cmd = %Q[skopeo  --policy #{dir}/policy.json copy --src-creds  #{src_user}:#{src_pass} docker://#{src_oci}:#{src_commit} dir:#{tar}]
          #   details = run_command(cmd)
          #   cmd = %Q[skopeo  --policy #{dir}/policy.json copy --dest-creds #{dst_user}:#{dst_pass} dir:#{tar} docker://#{dst_oci}:#{dst_commit}]
          #   details = run_command(cmd)
          # end
        end
        if details[:status] == 1
          # Error occured
          # Logger: ("Error copying image:\n#{details[:err]}")
          raise "Error copying image from registry to registry #{details[:err]}."
        end
        details
      rescue Exception => e
        # Logger: ("Error caught copying image: #{e.message}.")
        if (retries += 1) < 3
          # Logger: ("Retry... ##{retries}.")
          sleep 10 * 2**retries # Exponential backoff
          retry
        end
        raise e
      end
    end
  end
end
