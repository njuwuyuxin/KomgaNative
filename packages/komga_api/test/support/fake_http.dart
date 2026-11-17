import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 假的 dio 适配器：不发网络请求，按调用返回预设响应，并记录请求。
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  final List<RequestOptions> requests = <RequestOptions>[];

  RequestOptions get lastRequest => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 直接回放一段**服务器原始响应文本**（fixture 用）。
ResponseBody rawResponse(
  String body, {
  int status = 200,
  String contentType = 'application/json',
}) => ResponseBody.fromString(
  body,
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[contentType],
  },
);

ResponseBody jsonResponse(Object body, {int status = 200}) =>
    rawResponse(jsonEncode(body), status: status);

ResponseBody bytesResponse(
  List<int> bytes, {
  String contentType = 'image/png',
}) => ResponseBody.fromBytes(
  bytes,
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[contentType],
  },
);

Dio dioWith(FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;
