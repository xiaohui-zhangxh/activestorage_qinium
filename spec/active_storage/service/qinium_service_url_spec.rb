# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveStorage::Service::QiniumService, "#url" do
  let(:key) { "tenant/b9da2gz9tmv5hm2llrke7xppktnc" }
  let(:chinese_filename) { "第一步：注册账号.docx" }

  def service_for(public:)
    described_class.new(
      public: public,
      bucket: "test-bucket",
      domain: "example.clouddn.com",
      access_key: "test_access_key",
      secret_key: "test_secret_key",
      protocol: "http"
    )
  end

  def expected_content_disposition_for(display_name)
    ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment",
      filename: ActiveStorage::Filename.new(display_name).sanitized
    )
  end

  def expect_attachment_query_params(url)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query.to_s).to_h
    yield params
  end

  context "when disposition is attachment" do
    it "includes attname and response-content-disposition for a Chinese filename (public bucket)" do
      service = service_for(public: true)
      url = service.url(key, disposition: :attachment, filename: chinese_filename)

      expect(url).to start_with("http://example.clouddn.com/")
      expect_attachment_query_params(url) do |params|
        expect(params["attname"]).to eq(chinese_filename)
        expect(params["response-content-disposition"]).to eq(expected_content_disposition_for(chinese_filename))
      end
    end

    it "uses basename of key as attname when filename is omitted (public bucket)" do
      service = service_for(public: true)
      url = service.url("org/sub/file.docx", disposition: :attachment)

      expect_attachment_query_params(url) do |params|
        expect(params["attname"]).to eq("file.docx")
        expect(params["response-content-disposition"]).to eq(expected_content_disposition_for("file.docx"))
      end
    end

    it "includes attname and response-content-disposition in private signed URL query" do
      service = service_for(public: false)
      url = service.url(key, disposition: :attachment, filename: chinese_filename)

      expect(url).to include("example.clouddn.com/#{CGI.escape(key.split('/').first)}/") # tenant segment encoded
      expect(url).to include("e=")
      expect(url).to include("token=")

      expect_attachment_query_params(url) do |params|
        expect(params["attname"]).to eq(chinese_filename)
        expect(params["response-content-disposition"]).to eq(expected_content_disposition_for(chinese_filename))
      end
    end
  end

  context "when disposition is inline" do
    it "does not add attachment-only params" do
      service = service_for(public: true)
      url = service.url(key, disposition: :inline, content_type: "application/pdf")

      expect(url).not_to include("attname=")
      expect(url).to include("response-content-disposition=inline")
      expect(url).to include("response-content-type=")
    end
  end
end
