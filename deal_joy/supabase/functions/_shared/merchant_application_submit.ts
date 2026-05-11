// 商家入驻申请写入（merchants + documents + 连锁品牌 + 邮件 + 活动日志）
// 由 merchant-register（本人 JWT）与 admin-merchant-onboard（管理员代提交）共用。

import { type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendEmail, getAdminRecipients } from "./email.ts";
import { logMerchantActivity, type MerchantActivityActorType } from "./merchant_activity_log.ts";
import { buildM1Email } from "./email-templates/merchant/welcome.ts";
import { buildM2Email } from "./email-templates/merchant/verification-pending.ts";
import { buildA2Email } from "./email-templates/admin/merchant-application.ts";

export interface MerchantRegisterRequestBody {
  company_name: string;
  contact_name: string;
  contact_email: string;
  phone: string;
  category: string;
  ein: string;
  address: string;
  city?: string;
  lat?: number;
  lng?: number;
  registration_type?: "single" | "multiple";
  brand_name?: string;
  brand_logo_url?: string;
  brand_description?: string;
  documents?: Array<{
    document_type: string;
    file_url: string;
    file_name?: string;
    file_size?: number;
    mime_type?: string;
  }>;
}

export interface SubmitMerchantApplicationOk {
  merchant_id: string;
  status: "pending";
  message: string;
  registration_type: string;
  brand_id?: string;
  submitted_at: string;
  is_resubmission: boolean;
}

export interface SubmitMerchantApplicationErr {
  error: string;
  status: number;
}

export function validateMerchantRegisterRequest(
  body: MerchantRegisterRequestBody,
): string | null {
  if (!body.company_name?.trim()) return "Company name is required";
  if (!body.contact_name?.trim()) return "Contact name is required";
  if (!body.contact_email?.trim()) return "Contact email is required";
  const contactTrim = body.contact_email.trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(contactTrim)) {
    return "Contact email must be a valid email address";
  }
  if (!body.phone?.trim()) return "Phone number is required";
  if (!body.category?.trim()) return "Business category is required";
  if (!body.ein?.trim()) return "EIN/Tax ID is required";

  const einPattern = /^\d{2}-\d{7}$/;
  if (!einPattern.test(body.ein.trim())) {
    return "EIN/Tax ID must be in format XX-XXXXXXX";
  }

  if (!body.address?.trim()) return "Store address is required";

  const validCategories = [
    "Restaurant",
    "SpaAndMassage",
    "HairAndBeauty",
    "Fitness",
    "FunAndGames",
    "NailAndLash",
    "Wellness",
    "Other",
  ];
  if (!validCategories.includes(body.category)) {
    return `Invalid category. Must be one of: ${validCategories.join(", ")}`;
  }

  return null;
}

/**
 * 执行入驻写入。ownerUserId 为门店 owner（auth.users.id）。
 * ownerAuthEmail：auth 用户邮箱（OAuth 可能为空，邮件侧用 contact 兜底）。
 */
export async function submitMerchantApplication(
  adminSupabase: SupabaseClient,
  params: {
    ownerUserId: string;
    ownerAuthEmail: string | null | undefined;
    body: MerchantRegisterRequestBody;
    activity: {
      actorType: MerchantActivityActorType;
      actorUserId: string;
      detail?: string | null;
    };
  },
): Promise<SubmitMerchantApplicationOk | SubmitMerchantApplicationErr> {
  const { ownerUserId, ownerAuthEmail, body, activity } = params;
  const submittedAtIso = new Date().toISOString();

  const { data: existingMerchant } = await adminSupabase
    .from("merchants")
    .select("id, status")
    .eq("user_id", ownerUserId)
    .maybeSingle();

  let merchantId: string;

  if (existingMerchant) {
    const { error: updateError } = await adminSupabase
      .from("merchants")
      .update({
        company_name: body.company_name,
        name: body.company_name,
        contact_name: body.contact_name,
        contact_email: body.contact_email,
        phone: body.phone,
        category: body.category,
        ein: body.ein,
        address: body.address,
        status: "pending",
        rejection_reason: null,
        submitted_at: submittedAtIso,
        updated_at: submittedAtIso,
      })
      .eq("id", existingMerchant.id);

    if (updateError) {
      console.error("[submitMerchantApplication] update merchant error:", updateError);
      return { error: "Failed to update merchant record", status: 500 };
    }

    merchantId = existingMerchant.id;

    await adminSupabase
      .from("merchant_documents")
      .delete()
      .eq("merchant_id", merchantId);
  } else {
    const profileEmail =
      (ownerAuthEmail && String(ownerAuthEmail).trim()) ||
      body.contact_email.trim();

    const { data: userProfile } = await adminSupabase
      .from("users")
      .select("id")
      .eq("id", ownerUserId)
      .maybeSingle();

    if (!userProfile) {
      await adminSupabase.from("users").insert({
        id: ownerUserId,
        email: profileEmail,
        full_name: body.contact_name,
        role: "merchant",
      });
    } else {
      const authEmail = ownerAuthEmail && String(ownerAuthEmail).trim();
      const userPatch: { role: string; email?: string } = {
        role: "merchant",
      };
      if (!authEmail) {
        userPatch.email = body.contact_email.trim();
      }
      await adminSupabase.from("users").update(userPatch).eq("id", ownerUserId);
    }

    const { data: newMerchant, error: insertError } = await adminSupabase
      .from("merchants")
      .insert({
        user_id: ownerUserId,
        company_name: body.company_name,
        name: body.company_name,
        contact_name: body.contact_name,
        contact_email: body.contact_email,
        phone: body.phone,
        category: body.category,
        ein: body.ein,
        address: body.address,
        city: body.city || null,
        lat: body.lat ?? null,
        lng: body.lng ?? null,
        status: "pending",
        submitted_at: submittedAtIso,
      })
      .select("id")
      .single();

    if (insertError || !newMerchant) {
      console.error("[submitMerchantApplication] insert merchant error:", insertError);
      return { error: "Failed to create merchant record", status: 500 };
    }

    merchantId = newMerchant.id;
  }

  const registrationType = body.registration_type ?? "single";
  if (registrationType === "multiple" && !existingMerchant) {
    const brandName = body.brand_name?.trim() || body.company_name;

    const { data: newBrand, error: brandError } = await adminSupabase
      .from("brands")
      .insert({
        name: brandName,
        logo_url: body.brand_logo_url ?? null,
        description: body.brand_description ?? null,
      })
      .select("id")
      .single();

    if (brandError || !newBrand) {
      console.error("[submitMerchantApplication] create brand error:", brandError);
    } else {
      await adminSupabase
        .from("merchants")
        .update({ brand_id: newBrand.id })
        .eq("id", merchantId);

      await adminSupabase
        .from("brand_admins")
        .insert({
          brand_id: newBrand.id,
          user_id: ownerUserId,
          role: "owner",
        });
    }
  }

  const docs = body.documents ?? [];
  if (docs.length > 0) {
    const docRows = docs.map((doc) => ({
      merchant_id: merchantId,
      document_type: doc.document_type,
      file_url: doc.file_url,
      file_name: doc.file_name ?? null,
      file_size: doc.file_size ?? null,
      mime_type: doc.mime_type ?? null,
    }));

    const { error: docsError } = await adminSupabase
      .from("merchant_documents")
      .insert(docRows);

    if (docsError) {
      console.error("[submitMerchantApplication] insert documents error:", docsError);
      if (!existingMerchant) {
        await adminSupabase.from("merchants").delete().eq("id", merchantId);
      }
      return { error: "Failed to save document records", status: 500 };
    }
  }

  await logMerchantActivity(adminSupabase, {
    merchant_id: merchantId,
    event_type: "application_submitted",
    actor_type: activity.actorType,
    actor_user_id: activity.actorUserId,
    detail: activity.detail ?? null,
    created_at: submittedAtIso,
  });

  let brandId: string | undefined;
  if (registrationType === "multiple") {
    const { data: merchantData } = await adminSupabase
      .from("merchants")
      .select("brand_id")
      .eq("id", merchantId)
      .single();
    brandId = merchantData?.brand_id ?? undefined;
  }

  try {
    const merchantEmail =
      (ownerAuthEmail && String(ownerAuthEmail).trim()) ||
      body.contact_email.trim();
    const merchantName = body.company_name;
    const isResubmission = !!existingMerchant;
    const submittedAt = submittedAtIso;

    if (!isResubmission && merchantEmail) {
      const { subject, html } = buildM1Email({
        merchantName,
        applicationId: merchantId,
      });
      await sendEmail(adminSupabase, {
        to: merchantEmail,
        subject,
        htmlBody: html,
        emailCode: "M1",
        referenceId: merchantId,
        recipientType: "merchant",
        merchantId,
      });
    }

    if (merchantEmail) {
      const { subject, html } = buildM2Email({
        merchantName,
        applicationId: merchantId,
        isResubmission,
      });
      await sendEmail(adminSupabase, {
        to: merchantEmail,
        subject,
        htmlBody: html,
        emailCode: "M2",
        referenceId: merchantId,
        recipientType: "merchant",
        merchantId,
      });
    }

    const adminEmails = await getAdminRecipients(adminSupabase, "A2");
    if (adminEmails.length > 0) {
      const { subject, html } = buildA2Email({
        merchantName,
        contactEmail: body.contact_email,
        submittedAt,
        merchantId,
        isResubmission,
      });
      await sendEmail(adminSupabase, {
        to: adminEmails,
        subject,
        htmlBody: html,
        emailCode: "A2",
        referenceId: merchantId,
        recipientType: "admin",
      });
    }
  } catch (emailErr) {
    console.error("[submitMerchantApplication] email error:", emailErr);
  }

  return {
    merchant_id: merchantId,
    status: "pending",
    message:
      "Application submitted successfully. Review takes 24-48 hours.",
    registration_type: registrationType,
    brand_id: brandId,
    submitted_at: submittedAtIso,
    is_resubmission: !!existingMerchant,
  };
}
