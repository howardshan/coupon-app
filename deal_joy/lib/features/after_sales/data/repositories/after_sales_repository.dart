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

  Future<List<AfterSalesRequestModel>> fetchRequests({String? orderId}) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      _functionName,
      method: HttpMethod.get,
      queryParameters: {
        'access_token': token,
        if (orderId != null) 'order_id': orderId,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    final list = (data?['requests'] as List<dynamic>? ?? const [])
        .map((item) => AfterSalesRequestModel.fromJson(item as Map<String, dynamic>))
        .toList();
    return list;
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
        'couponId': couponId,
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
    await _putSignedFile(slot, bytes, await file.mimeType);
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
