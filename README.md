# ActiveStorage Qinium

[![Gem Version](https://badge.fury.io/rb/activestorage_qinium.svg)](https://badge.fury.io/rb/activestorage_qinium)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Active Storage 的七牛云存储服务扩展，支持多租户配置和图片分析器。

## 功能特性

- **完整 Active Storage 支持**：实现所有必需的服务方法（upload、download、delete、url 等）
- **分块上传**：支持大文件分块上传，断点续传
- **公有/私有空间**：支持七牛云公有和私有 bucket 配置
- **自定义图片分析器**：利用七牛云 imageInfo API 获取图片元数据
- **直接上传**：支持浏览器直传七牛云，减轻服务器压力
- **URL 参数支持**：支持 disposition、content_type、fop 等参数自定义
- **多租户支持**：通过 qinium gem 实现灵活的多租户配置

## 安装

添加到你的 Gemfile：

```ruby
gem 'activestorage_qinium', '~> 0.4'
```

然后执行：

```bash
$ bundle install
```

## 配置

### 基础配置

在 `config/storage.yml` 中配置七牛云存储：

```yaml
# 公有空间（适合图片、静态资源）
qiniu_public:
  service: Qinium
  public: true
  bucket: your-public-bucket
  domain: your-domain.clouddn.com
  access_key: <%= ENV['QINIU_ACCESS_KEY'] %>
  secret_key: <%= ENV['QINIU_SECRET_KEY'] %>
  protocol: https
  block_size: 4194304  # 可选，分块大小（字节），默认 4MB
  expires_in: 3600       # 可选，私有 URL 过期时间（秒）

# 私有空间（适合敏感文件）
qiniu_private:
  service: Qinium
  public: false
  bucket: your-private-bucket
  domain: your-private-domain.clouddn.com
  access_key: <%= ENV['QINIU_ACCESS_KEY'] %>
  secret_key: <%= ENV['QINIU_SECRET_KEY'] %>
  protocol: https
```

### 环境变量

```bash
export QINIU_ACCESS_KEY=your_access_key
export QINIU_SECRET_KEY=your_secret_key
```

### 多租户配置

通过 Qinium gem 的配置系统实现多租户：

```ruby
# config/initializers/qinium.rb
Qinium.configure do |config|
  config.tenant_settings = {
    tenant_a: {
      bucket: 'tenant-a-bucket',
      access_key: ENV['TENANT_A_ACCESS_KEY'],
      secret_key: ENV['TENANT_A_SECRET_KEY']
    },
    tenant_b: {
      bucket: 'tenant-b-bucket',
      access_key: ENV['TENANT_B_ACCESS_KEY'],
      secret_key: ENV['TENANT_B_SECRET_KEY']
    }
  }
end
```

## 使用

### 基本使用

```ruby
# 存储文件
user.avatar.attach(io: File.open('/path/to/avatar.jpg'), filename: 'avatar.jpg')

# 获取 URL
user.avatar.url           # 内联显示
user.avatar.url(disposition: :attachment)  # 下载附件
user.avatar.url(disposition: :attachment, filename: "自定义文件名.jpg")

# 图片处理（fop 参数）
user.avatar.url(fop: 'imageView2/0/w/200/h/200')
```

### 直接上传（浏览器直传）

```erb
<%= form_with model: @user, local: true do |form| %>
  <%= form.file_field :avatar, 
      direct_upload: true,
      data: { 
        direct_upload_url: rails_direct_uploads_url 
      } %>
  <%= form.submit %>
<% end %>
```

### URL 参数详解

```ruby
# 强制下载
blob.url(disposition: :attachment)
blob.url(disposition: :attachment, filename: "报告.pdf")

# 自定义响应头（仅公有资源支持）
blob.url(
  response_content_type: "application/octet-stream",
  response_cache_control: "max-age=3600",
  response_content_disposition: "attachment; filename=doc.pdf"
)

# 下载限速（单位：bit/s，范围 819200 ~ 838860800）
blob.url(traffic_limit: 819200)

# 图片处理
blob.url(fop: 'imageInfo')           # 图片信息
blob.url(fop: 'imageView2/2/w/200')  # 缩略图
blob.url(fop: 'imageMogr2/rotate/90') # 旋转
```

## 图片分析器

QiniumImageAnalyzer 利用七牛云 imageInfo API 获取图片元数据：

```ruby
# 自动注册的分析器
ActiveStorage::Service::QiniumService.analyzers
# => [ActiveStorage::Analyzer::QiniumImageAnalyzer]

# 获取图片元数据
blob.metadata
# => {
#   size: 39504,
#   format: "jpg",
#   width: 708,
#   height: 576,
#   colorModel: "ycbcr"
# }
```

## 支持的 Active Storage 版本

| Gem 版本 | Active Storage 版本 |
|---------|-------------------|
| 0.4.x   | >= 6.1            |

## 开发

克隆仓库后运行测试：

```bash
$ bundle install
$ bundle exec rspec
```

运行特定测试：

```bash
$ bundle exec rspec spec/active_storage/service/qinium_service_url_spec.rb
$ bundle exec rspec spec/active_storage/service/qinium_service_spec.rb
```

## 贡献

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 许可证

[MIT 许可证](https://opensource.org/licenses/MIT)

## 相关项目

- [qinium](https://github.com/xiaohui-zhangxh/qinium) - 底层七牛云 SDK
- [Active Storage](https://edgeguides.rubyonrails.org/active_storage_overview.html) - Rails 官方文档
- [七牛云文档](https://developer.qiniu.com/kodo) - 七牛云开发者中心
