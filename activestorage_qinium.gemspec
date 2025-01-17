# frozen_string_literal: true

require_relative "lib/active_storage_qinium/version"

Gem::Specification.new do |spec|
  spec.name = "activestorage_qinium"
  spec.version = ActiveStorageQinium::VERSION
  spec.authors = ["xiaohui"]
  spec.email = ["xiaohui@tanmer.com"]

  spec.summary = "A muti-tenant SDK wrap the Qiniu Storage Service as an Active Storage service"
  spec.description = "Wraps the Qiniu Storage Service as an Active Storage service, support muti-tenant settings. https://www.qiniu.com"
  spec.homepage = "https://github.com/xiaohui-zhangxh/activestorage_qinium"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "qinium", "~> 0.4.0"
end
