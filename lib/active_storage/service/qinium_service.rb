require 'open-uri'
require 'active_storage/analyzer/qinium_image_analyzer'
module ActiveStorage
  class Service::QiniumService < Service
    attr_reader :qiniu

    delegate :config, :client, to: :qiniu
    delegate :settings, :public, :bucket, :access_key, :secret_key, :domain,
              :protocol, :put_policy_options,
             to: :config

    def self.analyzers
      [ActiveStorage::Analyzer::QiniumImageAnalyzer]
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
      'POST'
    end

    def http_response_type_for_direct_upload
      'json'
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
        ':file': 'file'
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
          ctx = data.fetch('ctx')
          host = data.fetch('host')
          file_size += blk.size
          blocks.push(ctx)
        end

        _code, data, _headers = qiniu.object.mkfile(token: up_token, file_size: file_size, key: key, mime_type: content_type, blocks: blocks)
        data
      end
    end

    def update_metadata(key, **metadata)
    end

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
                     'Range' => "bytes=#{range.begin}-#{range.exclude_end? ? range.end - 1 : range.end}").body
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
        items_for(prefix).each { |item| delete item['key'] }
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
        fop = if options[:fop].present? # 内容预处理
                options[:fop]
              elsif options[:disposition].to_s == 'attachment' # 下载附件
                attname = URI.encode_www_form_component "#{options[:filename] || key}"
                "attname=#{attname}"
              end

        url = if public
                url_encoded_key = key.split('/').map { |x| CGI.escape(x) }.join('/')
                ["#{protocol}://#{domain}/#{url_encoded_key}", fop].compact.join('?')
              else
                expires_in = options[:expires_in] ||
                             Rails.application.config.active_storage.service_urls_expire_in ||
                             3600
                Qinium::Auth.authorize_download_url(domain, key,
                                                  access_key, secret_key,
                                                  schema: protocol, fop: fop, expires_in: expires_in)
              end

        payload[:url] = url
        url
      end
    end

    private

    def items_for(prefix = '')
      _code, data, _headers = qiniu.object.list(prefix: prefix)
      data['items']
    end

    def upload_blk(blk, token:, host: nil)
      with_retries max: 3 do
        _code, data, _headers = qiniu.object.mkblk(blk, token: token, host: host)
        data
      end
    end

    def with_retries(max: 3)
      yield
    rescue
      raise if max.zero?
      max -= 1
      retry
    end
  end
end
