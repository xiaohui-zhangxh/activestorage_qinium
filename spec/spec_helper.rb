# frozen_string_literal: true

require "bundler/setup"
require "openssl"
require "active_support/core_ext/string"
require "active_storage"
# ActiveStorage::Filename 在 app/models 下，非 Rails 完整加载时需单独引入
as_spec = Gem.loaded_specs["activestorage"] || Gem::Specification.find_by_name("activestorage")
as_root = as_spec.full_gem_path
$LOAD_PATH.unshift("#{as_root}/app/models") unless $LOAD_PATH.include?("#{as_root}/app/models")
require "active_storage/filename"
require "qinium"
require_relative "../lib/active_storage/service/qinium_service"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

# QiniumService#url（私有空间分支）会读 Rails 配置
unless defined?(Rails) && Rails.respond_to?(:application)
  module Rails
    class << self
      def application
        @application ||= Struct.new(:config).new(
          Struct.new(:active_storage).new(
            Struct.new(:service_urls_expire_in).new(3600)
          )
        )
      end
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
