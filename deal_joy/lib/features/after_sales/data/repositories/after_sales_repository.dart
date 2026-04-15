import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../models/after_sales_request_model.dart';

class AfterSalesRepository {
  AfterSalesRepository(this._client, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;
  static const _functionName = 'after-sales-request';

  /// 仅当为合法 UUID 时才传给 Edge（与 coupons.id 一致）；否则只传 orderId，由服务端解析。
  static bool _looksLikeCouponUuid(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(s);
  }

  Future<List<AfterSalesRequestModel>> fetchRequests({String? orderId}) async {
    final token = _requireToken();
    try {
      // 使用 Authorization，避免 JWT 仅出现在 query 导致 URL 过长或被网关截断；Edge resolveUser 支持 header
      final response = await _client.functions.invoke(
        _functionName,
        method: HttpMethod.get,
        headers: {'Authorization': 'Bearer $token'},
        queryParameters: {
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
        },
      );
      final raw = response.data;
      if (raw is! Map) {
        throw const AppException(
          'Unexpected response from after-sales. Please try again.',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      if (data.containsKey('error')) {
        throw AppException(
          data['message'] as String? ?? data['error'].toString(),
          code: data['error'] as String?,
        );
      }
      final rawList = data['requests'];
      if (rawList != null && rawList is! List) {
        throw const AppException('Invalid after-sales list format.');
      }
      return (rawList as List<dynamic>? ?? const [])
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const AppException('Invalid after-sales entry.');
            }
            return AfterSalesRequestModel.fromJson(item);
          })
          .toList();
    } on FunctionException catch (e) {
      throw AppException(_messageFromFunctionException(e));
    }
  }

  /// 将 Edge 非 2xx 转为用户可读文案
  static String _messageFromFunctionException(FunctionException e) {
    final details = e.details;
    if (details is Map) {
      final msg = details['message'];
      if (msg != null && msg.toString().trim().isNotEmpty) {
        return msg.toString();
      }
      final err = details['error'];
      if (err != null && err.toString().trim().isNotEmpty) {
        return err.toString();
      }
    }
    if (e.status == 401) {
      return 'Session expired. Please sign in again.';
    }
    return 'Could not load after-sales (HTTP ${e.status}). Check network and tap Retry.';
  }

  Future<AfterSalesRequestModel?> fetchLatestForOrder(String orderId) async {
    final requests = await fetchRequests(orderId: orderId);
    if (requests.isEmpty) return null;
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return requests.first;
  }

  Future<AfterSalesRequestModel> submitRequest({
    required String orderId,
    required String couponId,
    required AfterSalesReason reason,
    required String detail,
    List<String> attachmentPaths = const [],
  }) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      _functionName,
      body: {
        'orderId': orderId,
        ...(_looksLikeCouponUuid(couponId)
            ? <String, dynamic>{'couponId': couponId.trim()}
            : <String, dynamic>{}),
        'reasonCode': reason.code,
        'reasonDetail': detail,
        'attachments': attachmentPaths,
        'access_token': token,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    // 透传后端业务错误（如 duplicate_request、window_expired 等）
    if (data != null && data.containsKey('error')) {
      throw AppException(
        data['message'] as String? ?? 'Request failed',
        code: data['error'] as String?,
      );
    }
    final requestJson = data?['request'] as Map<String, dynamic>?;
    if (requestJson == null) {
      throw const AppException('Failed to submit after-sales request');
    }
    return AfterSalesRequestModel.fromJson(requestJson);
  }

  Future<AfterSalesRequestModel?> escalate(String requestId) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      '$_functionName/$requestId/escalate',
      method: HttpMethod.post,
      body: {
        'access_token': token,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    final requestJson = data?['request'] as Map<String, dynamic>?;
    return requestJson == null
        ? null
        : AfterSalesRequestModel.fromJson(requestJson);
  }

  Future<String> uploadEvidence(XFile file) async {
    final token = _requireToken();
    final fileName = file.name.isNotEmpty ? file.name : 'evidence.jpg';
    final slotResponse = await _client.functions.invoke(
      '$_functionName/uploads',
      method: HttpMethod.post,
      body: {
        'files': [
          {'filename': fileName},
        ],
        'access_token': token,
      },
    );
    final uploads = slotResponse.data is Map<String, dynamic>
        ? (slotResponse.data as Map<String, dynamic>)['uploads'] as List<dynamic>?
        : null;
    if (uploads == null || uploads.isEmpty) {
      throw const AppException('Failed to request upload slot');
    }
    final slot = AfterSalesUploadSlot.fromJson(uploads.first as Map<String, dynamic>);
    final bytes = await file.readAsBytes();
    await _putSignedFile(slot, bytes, file.mimeType);
    return slot.path;
  }

  Future<void> _putSignedFile(
    AfterSalesUploadSlot slot,
    Uint8List bytes,
    String? mimeType,
  ) async {
    final uri = Uri.parse(slot.signedUrl);
    final response = await _http.put(
      uri,
      headers: {
        'Authorization': 'Bearer ${slot.token}',
        'Content-Type': mimeType ?? 'application/octet-stream',
        'x-upsert': 'false',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('Upload failed (${response.statusCode})');
    }
  }

  String _requireToken() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AppAuthException('Please sign in to continue');
    }
    return token;
  }

  void dispose() {
    _http.close();
  }
}
