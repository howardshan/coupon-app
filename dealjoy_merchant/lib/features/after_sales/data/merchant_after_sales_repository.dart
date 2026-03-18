import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'merchant_after_sales_request.dart';

class AfterSalesListResult {
  const AfterSalesListResult({
    required this.requests,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<MerchantAfterSalesRequest> requests;
  final int total;
  final int page;
  final int perPage;

  bool get hasMore => requests.length < total;
}

class MerchantAfterSalesRepository {
  MerchantAfterSalesRepository(this._client, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;
  static const _functionName = 'merchant-after-sales';

  Future<AfterSalesListResult> fetchRequests({
    String status = 'pending,awaiting_platform',
    int page = 1,
    int perPage = 20,
  }) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      _functionName,
      method: HttpMethod.get,
      queryParameters: {
        'status': status,
        'page': '$page',
        'per_page': '$perPage',
        'access_token': token,
      },
      headers: {
        'Authorization': 'Bearer $token',
        'x-app-bearer': token,
      },
    );

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw const AfterSalesException('Failed to load after-sales requests');
    }
    final list = (data['data'] as List<dynamic>? ?? const [])
        .map((item) => MerchantAfterSalesRequest.fromJson(item as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? list.length;
    final resultPage = (data['page'] as num?)?.toInt() ?? page;
    final resultPerPage = (data['per_page'] as num?)?.toInt() ?? perPage;
    return AfterSalesListResult(
      requests: list,
      total: total,
      page: resultPage,
      perPage: resultPerPage,
    );
  }

  Future<MerchantAfterSalesRequest> fetchDetail(String requestId) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      '$_functionName/$requestId',
      method: HttpMethod.get,
      queryParameters: {
        'access_token': token,
      },
      headers: {
        'Authorization': 'Bearer $token',
        'x-app-bearer': token,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    final requestJson = data?['request'] as Map<String, dynamic>? ?? data;
    if (requestJson == null) {
      throw const AfterSalesException('Request not found', code: 'not_found');
    }
    return MerchantAfterSalesRequest.fromJson(requestJson);
  }

  Future<MerchantAfterSalesRequest> approve({
    required String requestId,
    required String note,
    List<String> attachments = const [],
  }) async {
    return _mutate(
      requestId,
      action: 'approve',
      payload: {
        'note': note,
        'attachments': attachments,
      },
    );
  }

  Future<MerchantAfterSalesRequest> reject({
    required String requestId,
    required String note,
    required List<String> attachments,
  }) async {
    if (attachments.isEmpty) {
      throw const AfterSalesException('At least one attachment is required');
    }
    return _mutate(
      requestId,
      action: 'reject',
      payload: {
        'note': note,
        'attachments': attachments,
      },
    );
  }

  Future<MerchantAfterSalesRequest> _mutate(
    String requestId, {
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final token = _requireToken();
    final response = await _client.functions.invoke(
      '$_functionName/$requestId/$action',
      method: HttpMethod.post,
      body: {
        ...payload,
        'access_token': token,
      },
      headers: {
        'Authorization': 'Bearer $token',
        'x-app-bearer': token,
      },
    );

    final data = response.data as Map<String, dynamic>?;
    final requestJson = data?['request'] as Map<String, dynamic>?;
    if (requestJson == null) {
      throw AfterSalesException(data?['message'] as String? ?? 'Update failed');
    }
    return MerchantAfterSalesRequest.fromJson(requestJson);
  }

  Future<String> uploadEvidence(XFile file) async {
    final token = _requireToken();
    final slotResponse = await _client.functions.invoke(
      '$_functionName/uploads',
      method: HttpMethod.post,
      body: {
        'files': [
          {'filename': file.name},
        ],
        'access_token': token,
      },
      headers: {
        'Authorization': 'Bearer $token',
        'x-app-bearer': token,
      },
    );

    final uploads = slotResponse.data is Map<String, dynamic>
        ? (slotResponse.data as Map<String, dynamic>)['uploads'] as List<dynamic>?
        : null;
    if (uploads == null || uploads.isEmpty) {
      throw const AfterSalesException('Failed to request upload slot');
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
      throw AfterSalesException('Upload failed (${response.statusCode})');
    }
  }

  String _requireToken() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AfterSalesException('Please sign in', code: 'unauthorized');
    }
    return token;
  }

  void dispose() {
    _http.close();
  }
}

class AfterSalesUploadSlot {
  const AfterSalesUploadSlot({
    required this.path,
    required this.signedUrl,
    required this.token,
    required this.bucket,
  });

  final String path;
  final String signedUrl;
  final String token;
  final String bucket;

  factory AfterSalesUploadSlot.fromJson(Map<String, dynamic> json) {
    return AfterSalesUploadSlot(
      path: json['path'] as String? ?? '',
      signedUrl: json['signedUrl'] as String? ?? '',
      token: json['token'] as String? ?? '',
      bucket: json['bucket'] as String? ?? 'after-sales-evidence',
    );
  }
}

class AfterSalesException implements Exception {
  const AfterSalesException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AfterSalesException($code): $message';
}
