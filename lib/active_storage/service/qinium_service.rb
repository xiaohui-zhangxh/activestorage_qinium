require "open-uri"
require "active_storage/analyzer/qinium_image_analyzer"
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
      instrument :fetch, source_bucket: source_bucket, source_key: source_key, target_bucket: target_bucket, target_key: target_key do
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
  
        disposition = options[:disposition].to_s.downcase
        content_type = options[:content_type]
  
        # 构建查询参数
        query_params = []
  
        if options[:fop].present? # 内容预处理
          query_params << options[:fop]
        elsif disposition == "attachment" # 下载附件
          attname = URI.encode_www_form_component (options[:filename] || key).to_s
          query_params << "attname=#{attname}"
        elsif disposition == "inline" # 预览（inline）
          # 明确设置 Content-Disposition 为 inline，确保浏览器预览而不是下载
          query_params << "response-content-disposition=inline"
          # 如果提供了 content_type，也设置 Content-Type 响应头
          # 这对于 PDF 文件特别重要，确保 Content-Type: application/pdf
          query_params << "response-content-type=#{URI.encode_www_form_component(content_type)}" if content_type.present?
        end
  
        # 构建 URL
        url = if config.public
                url_encoded_key = key.split("/").map { |x| CGI.escape(x) }.join("/")
                base_url = "#{protocol}://#{domain}/#{url_encoded_key}"
                query_params.any? ? "#{base_url}?#{query_params.join('&')}" : base_url
              else
                expires_in = options[:expires_in] ||
                             Rails.application.config.active_storage.service_urls_expire_in ||
                             3600
                # 对于私有资源，需要将查询参数传递给授权 URL 生成
                fop = query_params.join('&') if query_params.any?
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
