# 反代与 TLS：实测记录与客户端行为

自建 Komga 大多数不在"系统信任链 + 标准端口"的理想状态里。这份文档只记**抓到的真实行为**
和客户端对应的处理，避免下次再从"错误号 400"开始猜。

## 实测对象

- 服务器：一台公网可达的 NAS Komga（openresty 反代，端口 `4433`）
- 客户端环境：Windows 上的 `curl`（Schannel）与 Dart 3.14（BoringSSL，与 App 同一实现）
- 记录时间：2026-11-17

## 证据

### 1. 明文打到 HTTPS 端口 → 400 + HTML

```text
$ curl -i http://<host>:4433/api/v2/users/me
HTTP/1.1 400 Bad Request
Server: openresty
Content-Type: text/html
...
<html><head><title>400 The plain HTTP request was sent to HTTPS port</title></head>
<body><center><h1>400 Bad Request</h1></center>
<center>The plain HTTP request was sent to HTTPS port</center>
```

响应体原样存在 `packages/komga_api/test/fixtures/proxy-400-plain-http.html`。

**这不是 Komga 的 400**：请求根本没到 Komga，是反代在 TLS 层前就拒绝了。
把它当 `KomgaBadRequestError` 会让用户去检查账号/参数，方向完全错。

### 2. 证书过期 → Dart 握手失败，且异常类型不是 `badCertificate`

```text
$ curl -v https://<host>:4433/
* schannel: next InitializeSecurityContext failed: SEC_E_CERT_EXPIRED

Dart 侧（同一张证书）：
DioException(type: DioExceptionType.unknown,
  error: HandshakeException: Handshake error in client (OS Error:
    CERTIFICATE_VERIFY_FAILED: certificate has expired))
```

证书本身：

| 字段 | 值 |
|---|---|
| Subject | `CN=*.yasai.site` |
| Issuer | `C=US, O=Let's Encrypt, CN=E7` |
| 有效期止 | `2026-07-19T11:26:15Z`（实测时已过期约 4 个月） |
| SHA-256 指纹 | `cbbdc431a9fd55ebdadf7fd4e57d1343d58e5c428d392c4177218f5df481c7ba` |

要点：**`DioExceptionType.badCertificate` 不会出现**。只按 dio 的 `type` 分类，
证书问题会落进"网络不可达"，用户被引去检查 Wi-Fi。

### 3. 接受该证书后，API 一切正常

```text
$ curl -k -H "X-API-Key: <key>" https://<host>:4433/api/v2/users/me   → 200
$ curl -k -H "X-API-Key: <key>" https://<host>:4433/api/v1/libraries  → 200
```

即：**没有 API 版本差异**。同一把 API Key 在页面端和客户端都能用，唯一差别是传输层。

## 客户端行为

| 场景 | 行为 |
|---|---|
| 用户填 `http://host:4433`（该端口只接受 HTTPS） | 自动换 `https://` 重试一次，成功后保存纠正后的地址 |
| 已在 `https` 仍收到该 400 | 不重试，提示"这个端口只支持 HTTPS"，附地址建议 |
| 证书过期 / 自签名 / 主机名不匹配 | 抓证书 → 弹"证书不受信任"面板（CN、颁发者、到期日、SHA-256 前 8 字节）→ 用户点"Connect anyway"才放行 |
| 用户确认后 | 指纹持久化，之后只放行这一张；换证书会再次询问 |
| 反代返回 HTML 错误页（502 等） | 从 `<title>` 抠出人话，不把整页 HTML 塞进提示 |
| 其他 400 | 仍是 `KomgaBadRequestError`（含 `ERR_*` 机器码） |

复现方式：

```bash
dart test packages/komga_api   # errors_test.dart / tls_test.dart
```

## 仍未验证

- iOS 端的同一路径：`dart:io` 在 iOS 也走 BoringSSL，行为应当一致，
  但**没有在真机上跑过**（无 macOS 环境）。
- 自签名 CA（非叶证书自签）与双向 TLS：没测，也没打算支持。
