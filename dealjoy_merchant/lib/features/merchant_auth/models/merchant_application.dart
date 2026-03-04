// 商家注册申请相关数据模型
// 包含: MerchantCategory, DocumentType, ApplicationStatus,
//       MerchantDocument, MerchantApplication

// ============================================================
// 商家类别枚举
// ============================================================
enum MerchantCategory {
  restaurant,
  spaAndMassage,
  hairAndBeauty,
  fitness,
  funAndGames,
  nailAndLash,
  wellness,
  other;

  /// 显示标签（UI 文案英文）
  String get label {
    switch (this) {
      case MerchantCategory.restaurant:
        return 'Restaurant';
      case MerchantCategory.spaAndMassage:
        return 'Spa & Massage';
      case MerchantCategory.hairAndBeauty:
        return 'Hair & Beauty';
      case MerchantCategory.fitness:
        return 'Fitness';
      case MerchantCategory.funAndGames:
        return 'Fun & Games';
      case MerchantCategory.nailAndLash:
        return 'Nail & Lash';
      case MerchantCategory.wellness:
        return 'Wellness';
      case MerchantCategory.other:
        return 'Other';
    }
  }

  /// 传给后端 API 的字符串值
  String get apiValue {
    switch (this) {
      case MerchantCategory.restaurant:
        return 'Restaurant';
      case MerchantCategory.spaAndMassage:
        return 'SpaAndMassage';
      case MerchantCategory.hairAndBeauty:
        return 'HairAndBeauty';
      case MerchantCategory.fitness:
        return 'Fitness';
      case MerchantCategory.funAndGames:
        return 'FunAndGames';
      case MerchantCategory.nailAndLash:
        return 'NailAndLash';
      case MerchantCategory.wellness:
        return 'Wellness';
      case MerchantCategory.other:
        return 'Other';
    }
  }

  /// 类别图标（Material Icons）
  String get iconName {
    switch (this) {
      case MerchantCategory.restaurant:
        return 'restaurant';
      case MerchantCategory.spaAndMassage:
        return 'spa';
      case MerchantCategory.hairAndBeauty:
        return 'content_cut';
      case MerchantCategory.fitness:
        return 'fitness_center';
      case MerchantCategory.funAndGames:
        return 'sports_esports';
      case MerchantCategory.nailAndLash:
        return 'back_hand';
      case MerchantCategory.wellness:
        return 'self_improvement';
      case MerchantCategory.other:
        return 'store';
    }
  }

  /// 从 API 字符串解析
  static MerchantCategory fromApiValue(String value) {
    return MerchantCategory.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => MerchantCategory.other,
    );
  }

  /// 返回该类别需要上传的证件类型列表（不含 EIN，EIN 是文本输入）
  List<DocumentType> get requiredDocuments {
    // 所有类别都需要的基础证件
    final List<DocumentType> docs = [
      DocumentType.businessLicense,
      DocumentType.ownerID,
      DocumentType.storefrontPhoto,
    ];

    // 根据类别追加额外证件
    switch (this) {
      case MerchantCategory.restaurant:
        docs.addAll([
          DocumentType.healthPermit,
          DocumentType.foodServiceLicense,
        ]);
      case MerchantCategory.spaAndMassage:
        docs.addAll([
          DocumentType.healthPermit,
          DocumentType.cosmetologyLicense,
          DocumentType.massageTherapyLicense,
        ]);
      case MerchantCategory.hairAndBeauty:
        docs.add(DocumentType.cosmetologyLicense);
      case MerchantCategory.fitness:
        docs.add(DocumentType.facilityLicense);
      case MerchantCategory.nailAndLash:
        docs.addAll([
          DocumentType.healthPermit,
          DocumentType.cosmetologyLicense,
        ]);
      case MerchantCategory.wellness:
        docs.add(DocumentType.massageTherapyLicense);
      case MerchantCategory.other:
        docs.add(DocumentType.generalBusinessPermit);
      case MerchantCategory.funAndGames:
        break; // 只需基础证件
    }

    return docs;
  }
}

// ============================================================
// 证件类型枚举
// ============================================================
enum DocumentType {
  businessLicense,
  healthPermit,
  foodServiceLicense,
  cosmetologyLicense,
  massageTherapyLicense,
  facilityLicense,
  generalBusinessPermit,
  storefrontPhoto,
  ownerID;

  /// UI 显示标签
  String get label {
    switch (this) {
      case DocumentType.businessLicense:
        return 'Business License';
      case DocumentType.healthPermit:
        return 'Health Permit';
      case DocumentType.foodServiceLicense:
        return 'Food Service License';
      case DocumentType.cosmetologyLicense:
        return 'Cosmetology License';
      case DocumentType.massageTherapyLicense:
        return 'Massage Therapy License';
      case DocumentType.facilityLicense:
        return 'Facility License';
      case DocumentType.generalBusinessPermit:
        return 'General Business Permit';
      case DocumentType.storefrontPhoto:
        return 'Storefront Photo';
      case DocumentType.ownerID:
        return 'Owner ID';
    }
  }

  /// 传给后端的字段名
  String get apiValue {
    switch (this) {
      case DocumentType.businessLicense:
        return 'business_license';
      case DocumentType.healthPermit:
        return 'health_permit';
      case DocumentType.foodServiceLicense:
        return 'food_service_license';
      case DocumentType.cosmetologyLicense:
        return 'cosmetology_license';
      case DocumentType.massageTherapyLicense:
        return 'massage_therapy_license';
      case DocumentType.facilityLicense:
        return 'facility_license';
      case DocumentType.generalBusinessPermit:
        return 'general_business_permit';
      case DocumentType.storefrontPhoto:
        return 'storefront_photo';
      case DocumentType.ownerID:
        return 'owner_id';
    }
  }

  /// 是否是图片类型（storefrontPhoto 只接受图片）
  bool get imageOnly {
    return this == DocumentType.storefrontPhoto;
  }
}

// ============================================================
// 申请审核状态枚举
// ============================================================
enum ApplicationStatus {
  pending,
  approved,
  rejected;

  /// UI 显示文案
  String get label {
    switch (this) {
      case ApplicationStatus.pending:
        return 'Under Review';
      case ApplicationStatus.approved:
        return 'Approved';
      case ApplicationStatus.rejected:
        return 'Rejected';
    }
  }

  /// 从数据库字符串解析
  static ApplicationStatus fromString(String value) {
    switch (value) {
      case 'approved':
        return ApplicationStatus.approved;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.pending;
    }
  }
}

// ============================================================
// 单个证件文件模型
// ============================================================
class MerchantDocument {
  const MerchantDocument({
    required this.documentType,
    required this.fileUrl,
    this.localPath,
    this.fileName,
    this.fileSize,
    this.mimeType,
  });

  final DocumentType documentType;
  final String fileUrl;       // Supabase Storage URL（上传后填充）
  final String? localPath;    // 本地临时文件路径（上传前使用）
  final String? fileName;
  final int? fileSize;
  final String? mimeType;

  /// 是否已上传到服务器
  bool get isUploaded => fileUrl.startsWith('http');

  /// 转为 API 请求格式
  Map<String, dynamic> toJson() => {
        'document_type': documentType.apiValue,
        'file_url': fileUrl,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (mimeType != null) 'mime_type': mimeType,
      };

  MerchantDocument copyWith({
    DocumentType? documentType,
    String? fileUrl,
    String? localPath,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) {
    return MerchantDocument(
      documentType: documentType ?? this.documentType,
      fileUrl: fileUrl ?? this.fileUrl,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}

// ============================================================
// 商家注册申请完整数据模型
// ============================================================
class MerchantApplication {
  const MerchantApplication({
    this.merchantId,
    // Step 1: 账号信息
    this.email = '',
    // Step 2: 公司信息
    this.companyName = '',
    this.contactName = '',
    this.contactEmail = '',
    this.phone = '',
    // Step 3: 类别
    this.category,
    // Step 4: EIN + 证件
    this.ein = '',
    this.documents = const [],
    // Step 5: 地址（拆分为多字段）
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.state = '',
    this.zipcode = '',
    // 状态
    this.status = ApplicationStatus.pending,
    this.rejectionReason,
    this.submittedAt,
  });

  final String? merchantId;       // 提交后由服务器返回
  final String email;
  final String companyName;
  final String contactName;
  final String contactEmail;
  final String phone;
  final MerchantCategory? category;
  final String ein;
  final List<MerchantDocument> documents;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String zipcode;
  final ApplicationStatus status;
  final String? rejectionReason;
  final DateTime? submittedAt;

  /// 是否完成所有必填步骤（可提交）
  bool get isReadyToSubmit {
    if (companyName.isEmpty ||
        contactName.isEmpty ||
        phone.isEmpty ||
        ein.isEmpty ||
        address1.isEmpty ||
        city.isEmpty ||
        state.isEmpty ||
        zipcode.isEmpty ||
        category == null) {
      return false;
    }
    // 校验 EIN 格式
    final einPattern = RegExp(r'^\d{2}-\d{7}$');
    if (!einPattern.hasMatch(ein)) return false;

    // 校验所有必需证件均已上传
    final requiredDocs = category!.requiredDocuments;
    for (final required in requiredDocs) {
      final uploaded =
          documents.any((d) => d.documentType == required && d.isUploaded);
      if (!uploaded) return false;
    }

    return true;
  }

  /// 获取指定类型的证件（可能为 null）
  MerchantDocument? getDocument(DocumentType type) {
    try {
      return documents.firstWhere((d) => d.documentType == type);
    } catch (_) {
      return null;
    }
  }

  /// 转为 API 请求体
  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'contact_name': contactName,
        'contact_email': contactEmail.isEmpty ? email : contactEmail,
        'phone': phone,
        'category': category?.apiValue ?? '',
        'ein': ein,
        'address': '$address1${address2.isNotEmpty ? ', $address2' : ''}, $city, $state $zipcode',
        'address1': address1,
        'address2': address2,
        'city': city,
        'state': state,
        'zipcode': zipcode,
        'documents': documents.map((d) => d.toJson()).toList(),
      };

  /// 从数据库记录解析（用于状态查询）
  factory MerchantApplication.fromJson(Map<String, dynamic> json) {
    return MerchantApplication(
      merchantId: json['id'] as String?,
      companyName: json['company_name'] as String? ?? '',
      contactName: json['contact_name'] as String? ?? '',
      contactEmail: json['contact_email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      category: json['category'] != null
          ? MerchantCategory.fromApiValue(json['category'] as String)
          : null,
      ein: json['ein'] as String? ?? '',
      address1: json['address1'] as String? ?? json['address'] as String? ?? '',
      address2: json['address2'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipcode: json['zipcode'] as String? ?? '',
      status: ApplicationStatus.fromString(json['status'] as String? ?? 'pending'),
      rejectionReason: json['rejection_reason'] as String?,
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : null,
    );
  }

  MerchantApplication copyWith({
    String? merchantId,
    String? email,
    String? companyName,
    String? contactName,
    String? contactEmail,
    String? phone,
    MerchantCategory? category,
    String? ein,
    List<MerchantDocument>? documents,
    String? address1,
    String? address2,
    String? city,
    String? state,
    String? zipcode,
    ApplicationStatus? status,
    String? rejectionReason,
    DateTime? submittedAt,
  }) {
    return MerchantApplication(
      merchantId: merchantId ?? this.merchantId,
      email: email ?? this.email,
      companyName: companyName ?? this.companyName,
      contactName: contactName ?? this.contactName,
      contactEmail: contactEmail ?? this.contactEmail,
      phone: phone ?? this.phone,
      category: category ?? this.category,
      ein: ein ?? this.ein,
      documents: documents ?? this.documents,
      address1: address1 ?? this.address1,
      address2: address2 ?? this.address2,
      city: city ?? this.city,
      state: state ?? this.state,
      zipcode: zipcode ?? this.zipcode,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }
}
