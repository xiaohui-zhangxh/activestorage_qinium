# Changelog

所有对 `activestorage_qinium` 的显著更改都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
并且本项目遵循 [语义化版本控制](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.4.2] - 2026-04-02

### Added

- 完善测试覆盖：添加 `upload`、`download`、`delete`、`copy`、`fetch`、`exist?` 等核心方法的测试
- 更新 README：添加详细配置示例、使用说明、URL 参数详解
- 添加 WebMock 测试依赖

### Fixed

- 修复 gemspec 中的拼写错误（muti-tenant -> multi-tenant）

## [0.4.1] - 2024-03-15

### Added

- 增强 URL 生成功能：支持更多响应头参数自定义
  - `response_content_type` - 自定义 Content-Type
  - `response_cache_control` - 自定义 Cache-Control
  - `response_content_disposition` - 自定义 Content-Disposition
  - `response_content_encoding` - 自定义 Content-Encoding
  - `response_content_language` - 自定义 Content-Language
  - `response_expires` - 自定义 Expires
  - `traffic_limit` - 下载限速
- 改进附件下载：使用 `attname` 和 `response-content-disposition` 双重参数确保浏览器正确下载
- 添加中文文件名下载支持

### Changed

- 优化 `url` 方法：重构查询参数构建逻辑
- 改进 URL 编码：对 key 的路径部分正确编码
- 完善私有资源下载：将 fop 参数传递给授权 URL 生成

## [0.4.0] - 2024-XX-XX

### Added

- 支持多租户配置
- 添加 `QiniumImageAnalyzer` 自定义图片分析器
- 实现 `http_response_type_for_direct_upload` 方法
- 支持 `update_metadata` 方法（空实现，因七牛云不支持此操作）

## [0.2.1] - 2024-05-09

### Added

- 支持私有空间下载 URL 生成
- 添加 `Qinium::Auth.authorize_download_url` 签名机制

## [0.1.0] - 2022-08-10

### Added

- 初始发布
- 实现 Active Storage 服务所有必需方法
- 支持七牛云公有空间
- 支持分块上传
- 支持直接上传（浏览器直传）
- 添加 `QiniumImageAnalyzer` 图片分析器
