require "open-uri"
require "active_storage/analyzer/qinium_image_analyzer"

# Optional +upload_host+ in Active Storage service config: fixed upload base URL (e.g. Qiniu transfer acceleration).
# When blank, Qinium::Config#up_host uses the UC API as before.
module ActiveStorage
  module QiniumUploadHostConfig
    def up_host(bucket = self.bucket)
      raw = self[:upload_host]
      if raw.present?
        normalize_qiniu_upload_base_url(raw.to_s)
      else
        super
      end
    end

    private

    def normalize_qiniu_upload_base_url(url)
      s = url.strip.sub(%r{/+\z}, "")
      return s if s.match?(%r{\Ahttps?://}i)

      proto = (protocol || :https).to_s
      proto = "https" unless proto == "http"
      "#{proto}://#{s.sub(%r{\A//+}, "")}"
    end
  end
end

Qinium::Config.prepend(ActiveStorage::QiniumUploadHostConfig) unless Qinium::Config.ancestors.include?(ActiveStorage::QiniumUploadHostConfig)

module ActiveStorage
  class Service::QiniumService < Service
    attr_reader :qiniu

    delegate :config, :client, to: :qiniu
    delegate :settings, :bucket, :access_key, :secret_key, :domain,
             :protocol, :put_policy_options,
             to: :config

    def self.analyzers
      @analyzers ||= [ActiveStorage::Analyzer::QiniumImageAnalyzer]
    end

    def initialize(options)
      @qiniu = Qinium.new(options)
    end

    def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:, custom_metadata:)
      instrument :url, key: key do |payload|
        url = config.up_host
        payload[:url] = url
        url
      end
    end

    def http_method_for_direct_upload
      "POST"
    end

    def http_response_type_for_direct_upload
      "json"
    end

    def form_data_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:, **)
      put_policy = Qinium::PutPolicy.new(config, key: key, expires_in: expires_in)
      put_policy.fsize_limit = content_length.to_i + 1000
      # OPTIMIZE: 暂时关闭文件类型限制，避免 xmind 文件无法上传
      put_policy.mime_limit = nil
      put_policy.detect_mime = 1
      put_policy.insert_only = 1
      {
        key: key,
        token: put_policy.to_token,
        ':file': "file"
      }
    end

    def upload(key, io, checksum: nil, content_type: nil, **)
      instrument :upload, key: key, checksum: checksum do
        io = File.open(io) unless io.respond_to?(:read)

        put_policy = Qinium::PutPolicy.new(config, key: key, expires_in: put_policy_options.expires_in)
        up_token = put_policy.to_token
        blocks = []
        file_size = 0
        host = nil
        while (blk = io.read(config.block_size))
          data = upload_blk(blk, token: up_token, host: host)
          ctx = data.fetch("ctx")
          host = data.fetch("host")
          file_size += blk.size
          blocks.push(ctx)
        end

        _code, data, _headers = qiniu.object.mkfile(token: up_token, file_size: file_size, key: key,
                                                    mime_type: content_type, blocks: blocks)
        data
      end
    end

    def update_metadata(key, **metadata); end

    def download(key)
      if block_given?
        instrument :streaming_download, key: key do
          URI.open(url(key, disposition: :attachment)) do |file|
            while data = file.read(64.kilobytes)
              yield data
            end
          end
        end
      else
        instrument :download, key: key do
          URI.open(url(key, disposition: :attachment)).read
        end
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        uri = URI(url(key, disposition: :attachment))
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |client|
          client.get(uri,
                     "Range" => "bytes=#{range.begin}-#{range.exclude_end? ? range.end - 1 : range.end}").body
        end
      end
    end

    def delete(key)
      instrument :delete, key: key do
        qiniu.object.delete(key)
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        items_for(prefix).each { |item| delete item["key"] }
      end
    end

    def fetch(target_url, key)
      instrument :fetch, target_url: target_url, key: key do
        qiniu.object.fetch(target_url, key)
      end
    end

    def copy(source_bucket, source_key, target_bucket, target_key)
      instrument :fetch, source_bucket: source_bucket, source_key: source_key, target_bucket: target_bucket,
                         target_key: target_key do
        qiniu.object.copy(source_bucket, source_key, target_bucket, target_key)
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        answer = items_for(key).any?
        payload[:exist] = answer
        answer
      end
    end

    def url(key, **options)
      instrument :url, key: key do |payload|
        # 根据七牛云文档：https://developer.qiniu.com/kodo/1659/download-setting
        # 1. 使用 attname 参数可以让浏览器下载而不是打开
        # 2. 使用 response-content-disposition 参数可以自定义 Content-Disposition 响应头
        # 3. 使用 response-content-type 参数可以自定义 Content-Type 响应头
        # 4. 使用 response-cache-control 参数可以自定义 Cache-Control 响应头
        # 5. 使用 response-content-encoding 参数可以自定义 Content-Encoding 响应头
        # 6. 使用 response-content-language 参数可以自定义 Content-Language 响应头
        # 7. 使用 response-expires 参数可以自定义 Expires 响应头
        # 8. 使用 X-Qiniu-Traffic-Limit 参数可以限制下载速度

        disposition = options[:disposition]
        content_type = options[:content_type]

        # 构建查询参数
        query_params = []

        # 内容预处理（图片处理、视频处理等）
        query_params << options[:fop] if options[:fop].present?

        # 处理 disposition 相关参数
        if disposition.to_s == "attachment" # 下载附件
          # attname：触发「下载」行为；部分节点仍用对象 key 填 Content-Disposition，须同时传 response-content-disposition。
          # 文档：https://developer.qiniu.com/kodo/1659/download-setting
          display_name = (options[:filename].presence || File.basename(key)).to_s
          query_params << "attname=#{URI.encode_www_form_component(display_name)}"
          # cd = ActionDispatch::Http::ContentDisposition.format(
          #   disposition: "attachment",
          #   filename: ActiveStorage::Filename.new(display_name).sanitized
          # )
          # query_params << "response-content-disposition=#{ERB::Util.url_encode(cd)}"
          # elsif disposition.to_s == "inline" # 预览（inline）
          #   # 明确设置 Content-Disposition 为 inline，确保浏览器预览而不是下载
          #   query_params << "response-content-disposition=inline"
        end

        # 自定义响应头参数
        # 注意：这些参数只有请求成功（即返回码为 200 OK）才会生效
        # 且不支持在匿名访问的下载请求中自定义标准响应头
        if options[:response_content_type].present? || content_type.present?
          value = options[:response_content_type] || content_type
          query_params << "response-content-type=#{URI.encode_www_form_component(value)}"
        end

        if options[:response_cache_control].present?
          query_params << "response-cache-control=#{URI.encode_www_form_component(options[:response_cache_control])}"
        end

        if options[:response_content_disposition].present?
          query_params << "response-content-disposition=#{ERB::Util.url_encode(options[:response_content_disposition])}"
        end

        if options[:response_content_encoding].present?
          query_params << "response-content-encoding=#{URI.encode_www_form_component(options[:response_content_encoding])}"
        end

        if options[:response_content_language].present?
          query_params << "response-content-language=#{URI.encode_www_form_component(options[:response_content_language])}"
        end

        if options[:response_expires].present?
          query_params << "response-expires=#{URI.encode_www_form_component(options[:response_expires])}"
        end

        # 下载限速：X-Qiniu-Traffic-Limit
        # 取值范围为 819200 ~ 838860800，单位为 bit/s
        query_params << "X-Qiniu-Traffic-Limit=#{options[:traffic_limit].to_i}" if options[:traffic_limit].present?

        # 构建 URL
        url = if config.public
                url_encoded_key = key.split("/").map { |x| CGI.escape(x) }.join("/")
                base_url = "#{protocol}://#{domain}/#{url_encoded_key}"
                query_params.any? ? "#{base_url}?#{query_params.join("&")}" : base_url
              else
                expires_in = options[:expires_in] ||
                             Rails.application.config.active_storage.service_urls_expire_in ||
                             3600
                # 对于私有资源，需要将查询参数传递给授权 URL 生成
                fop = query_params.join("&") if query_params.any?
                Qinium::Auth.authorize_download_url(domain, key,
                                                    access_key, secret_key,
                                                    schema: protocol, fop: fop, expires_in: expires_in)
              end

        payload[:url] = url
        url
      end
    end

    private

    def items_for(prefix = "")
      _code, data, _headers = qiniu.object.list(prefix: prefix)
      data["items"]
    end

    def upload_blk(blk, token:, host: nil)
      with_retries max: 3 do
        _code, data, _headers = qiniu.object.mkblk(blk, token: token, host: host)
        data
      end
    end

    def with_retries(max: 3)
      yield
    rescue StandardError
      raise if max.zero?

      max -= 1
      retry
    end
  end
end
