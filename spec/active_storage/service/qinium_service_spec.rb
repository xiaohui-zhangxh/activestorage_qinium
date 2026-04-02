# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveStorage::Service::QiniumService do
  let(:service_options) do
    {
      public: true,
      bucket: "test-bucket",
      domain: "example.clouddn.com",
      access_key: "test_access_key",
      secret_key: "test_secret_key",
      protocol: "http",
      block_size: 1024 * 1024
    }
  end

  let(:service) { described_class.new(service_options) }
  let(:key) { "test/file.txt" }

  describe "#upload" do
    let(:io) { StringIO.new("test content") }
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_config) { instance_double(Qinium::Config) }
    let(:mock_object) { instance_double(Qinium::Object) }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:config).and_return(mock_config)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
      allow(mock_config).to receive(:block_size).and_return(1024 * 1024)
      allow(mock_config).to receive(:up_host).and_return("http://up.example.com")
    end

    it "uploads content to the storage" do
      allow(mock_object).to receive(:mkblk).and_return([200, { "ctx" => "context1", "host" => "host1" }, {}])
      allow(mock_object).to receive(:mkfile).and_return([200, { "key" => key }, {}])

      result = service.upload(key, io, checksum: nil, content_type: "text/plain")

      expect(result).to be_a(Hash)
      expect(result["key"]).to eq(key)
    end

    it "handles file path input" do
      Tempfile.create("test_upload") do |file|
        file.write("test content from file")
        file.rewind

        allow(mock_object).to receive(:mkblk).and_return([200, { "ctx" => "context1", "host" => "host1" }, {}])
        allow(mock_object).to receive(:mkfile).and_return([200, { "key" => key }, {}])

        result = service.upload(key, file.path, checksum: nil, content_type: "text/plain")

        expect(result).to be_a(Hash)
      end
    end
  end

  describe "#download" do
    let(:mock_response) { instance_double(Net::HTTPSuccess, read: "downloaded content") }

    before do
      stub_request(:get, /example\.clouddn\.com/)
        .to_return(status: 200, body: "downloaded content")
    end

    it "downloads content without block" do
      allow(service).to receive(:url).with(key, disposition: :attachment).and_return("http://example.clouddn.com/test/file.txt")

      content = service.download(key)

      expect(content).to be_a(String)
    end

    it "streams download with block" do
      allow(service).to receive(:url).with(key, disposition: :attachment).and_return("http://example.clouddn.com/test/file.txt")

      chunks = []
      service.download(key) do |chunk|
        chunks << chunk
      end

      expect(chunks).not_to be_empty
    end
  end

  describe "#download_chunk" do
    before do
      stub_request(:get, /example\.clouddn\.com/)
        .with(headers: { "Range" => "bytes=0-99" })
        .to_return(status: 206, body: "chunk content")
    end

    it "downloads a specific byte range" do
      allow(service).to receive(:url).with(key, disposition: :attachment).and_return("http://example.clouddn.com/test/file.txt")

      content = service.download_chunk(key, 0..99)

      expect(content).to be_a(String)
    end
  end

  describe "#delete" do
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_object) { instance_double(Qinium::Object) }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
      allow(mock_object).to receive(:delete).with(key).and_return([200, {}, {}])
    end

    it "deletes the object from storage" do
      expect { service.delete(key) }.not_to raise_error
    end
  end

  describe "#delete_prefixed" do
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_object) { instance_double(Qinium::Object) }
    let(:prefix) { "test/" }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
      allow(mock_object).to receive(:list)
        .with(prefix: prefix)
        .and_return([200, { "items" => [{ "key" => "test/file1.txt" }, { "key" => "test/file2.txt" }] }, {}])
      allow(mock_object).to receive(:delete)
    end

    it "deletes all objects with the given prefix" do
      expect(mock_object).to receive(:delete).with("test/file1.txt")
      expect(mock_object).to receive(:delete).with("test/file2.txt")

      service.delete_prefixed(prefix)
    end
  end

  describe "#exist?" do
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_object) { instance_double(Qinium::Object) }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
    end

    it "returns true when object exists" do
      allow(mock_object).to receive(:list)
        .with(prefix: key)
        .and_return([200, { "items" => [{ "key" => key }] }, {}])

      expect(service.exist?(key)).to be true
    end

    it "returns false when object does not exist" do
      allow(mock_object).to receive(:list)
        .with(prefix: key)
        .and_return([200, { "items" => [] }, {}])

      expect(service.exist?(key)).to be false
    end
  end

  describe "#copy" do
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_object) { instance_double(Qinium::Object) }
    let(:source_bucket) { "source-bucket" }
    let(:source_key) { "source/file.txt" }
    let(:target_bucket) { "target-bucket" }
    let(:target_key) { "target/file.txt" }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
      allow(mock_object).to receive(:copy)
        .with(source_bucket, source_key, target_bucket, target_key)
        .and_return([200, { "key" => target_key }, {}])
    end

    it "copies object from source to target" do
      result = service.copy(source_bucket, source_key, target_bucket, target_key)

      expect(result).to be_a(Hash)
      expect(result["key"]).to eq(target_key)
    end
  end

  describe "#fetch" do
    let(:mock_qiniu) { instance_double(Qinium) }
    let(:mock_object) { instance_double(Qinium::Object) }
    let(:target_url) { "http://example.com/remote-file.txt" }

    before do
      allow(service).to receive(:qiniu).and_return(mock_qiniu)
      allow(mock_qiniu).to receive(:object).and_return(mock_object)
      allow(mock_object).to receive(:fetch)
        .with(target_url, key)
        .and_return([200, { "key" => key }, {}])
    end

    it "fetches remote file to storage" do
      result = service.fetch(target_url, key)

      expect(result).to be_a(Hash)
      expect(result["key"]).to eq(key)
    end
  end

  describe "#url_for_direct_upload" do
    let(:mock_config) { instance_double(Qinium::Config) }

    before do
      allow(service).to receive(:config).and_return(mock_config)
      allow(mock_config).to receive(:up_host).and_return("http://up.example.com")
    end

    it "returns upload URL" do
      url = service.url_for_direct_upload(
        key,
        expires_in: 3600,
        content_type: "text/plain",
        content_length: 100,
        checksum: "abc123",
        custom_metadata: {}
      )

      expect(url).to eq("http://up.example.com")
    end
  end

  describe "#form_data_for_direct_upload" do
    let(:mock_config) { instance_double(Qinium::Config) }
    let(:mock_put_policy) { instance_double(Qinium::PutPolicy) }

    before do
      allow(service).to receive(:config).and_return(mock_config)
      allow(Qinium::PutPolicy).to receive(:new).and_return(mock_put_policy)
      allow(mock_put_policy).to receive(:fsize_limit=)
      allow(mock_put_policy).to receive(:mime_limit=)
      allow(mock_put_policy).to receive(:detect_mime=)
      allow(mock_put_policy).to receive(:insert_only=)
      allow(mock_put_policy).to receive(:to_token).and_return("upload_token_123")
    end

    it "returns form data for direct upload" do
      form_data = service.form_data_for_direct_upload(
        key,
        expires_in: 3600,
        content_type: "text/plain",
        content_length: 100,
        checksum: "abc123"
      )

      expect(form_data).to include(key: key)
      expect(form_data).to include(token: "upload_token_123")
      expect(form_data).to include(:':file' => "file")
    end
  end

  describe "#http_method_for_direct_upload" do
    it "returns POST" do
      expect(service.http_method_for_direct_upload).to eq("POST")
    end
  end

  describe "#http_response_type_for_direct_upload" do
    it "returns json" do
      expect(service.http_response_type_for_direct_upload).to eq("json")
    end
  end

  describe "#update_metadata" do
    it "accepts metadata but does nothing (七牛云不支持此操作)" do
      expect { service.update_metadata(key, content_type: "application/json") }.not_to raise_error
    end
  end

  describe "analyzers" do
    it "returns custom image analyzer" do
      analyzers = described_class.analyzers

      expect(analyzers).to include(ActiveStorage::Analyzer::QiniumImageAnalyzer)
    end
  end
end
