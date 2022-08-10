module ActiveStorage
  # Extracts width and height in pixels from an image blob.
  #
  # Example:
  #
  #   ActiveStorage::Analyzer::QiniuImageAnalyzer.new(blob).metadata
  #   # => {:size=>39504, :format=>"gif", :width=>708, :height=>576, :colorModel=>"palette0", :frameNumber=>1}
  #
  class Analyzer::QiniumImageAnalyzer < Analyzer
    def self.accept?(blob)
      blob.image?
    end

    def metadata
      _code, data, _headers = blob.service.qiniu.client.get(blob.service.url(blob.key, fop: 'imageInfo'))
      data.symbolize_keys
    rescue StandardError
      {}
    end
  end
end
