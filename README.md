# curl-openssl-win

Windows **libcurl + OpenSSL** 预编译包，供 `rim-agent` 及其他项目统一使用（**不依赖 Qt Network / Schannel**）。

## 产物矩阵（GitHub Actions → Release Assets）

| 文件名模式 | 工具链 | 链接 |
|-----------|--------|------|
| `curl-openssl-*-windows-msvc-x64-static.zip` | MSVC x64 | 静态 `.lib` |
| `curl-openssl-*-windows-msvc-x64-shared.zip` | MSVC x64 | 动态 `.dll` + import `.lib` |
| `curl-openssl-*-windows-mingw-x64-static.zip` | MinGW-w64 x64 | 静态 `.a` |
| `curl-openssl-*-windows-mingw-x64-shared.zip` | MinGW-w64 x64 | 动态 `.dll` + `.dll.a` |

每个 zip 布局：

```
include/curl/...
include/openssl/...
lib/...
bin/...          # shared 包才有
share/cmake/CurlOpenSSL/CurlOpenSSLConfig.cmake
VERSION.txt
```

默认版本：`curl 8.11.1` + `OpenSSL 3.3.2`（可用 workflow_dispatch / tag 覆盖）。

## 消费方式（CMake）

```cmake
# 解压 Release zip 后：
set(CurlOpenSSL_ROOT "C:/deps/curl-openssl-windows-msvc-x64-static")
list(APPEND CMAKE_PREFIX_PATH "${CurlOpenSSL_ROOT}")
find_package(CurlOpenSSL REQUIRED)

target_link_libraries(myapp PRIVATE CurlOpenSSL::curl)
# 同时提供 CURL::libcurl 别名，兼容现有 find_package(CURL) 写法
```

环境变量 / CMake 缓存：

| 变量 | 说明 |
|------|------|
| `CURL_OPENSSL_ROOT` / `CurlOpenSSL_ROOT` | 解压根目录 |
| `MED_CURL_OPENSSL_URL` | （可选）Release zip URL，构建时自动下载 |

## 触发构建

- Push tag `v*` → 打 Release 并上传全部矩阵
- `workflow_dispatch` → 可选手动版本号

## 许可证

上游 [curl](https://curl.se/docs/copyright.html) / [OpenSSL](https://www.openssl.org/source/license.html) 许可证随包 `LICENSE-*` 文件分发。
