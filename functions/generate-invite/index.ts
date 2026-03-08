import { createClient } from "jsr:@supabase/supabase-js@2";
import { AuthMiddleware } from "../_shared/auth.ts";

/** Generate a URL-safe 32-byte random token. */
function generateToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // JWT is cryptographically verified by AuthMiddleware — safe to decode claims
  const authHeader = req.headers.get("Authorization")!;
  let claims: Record<string, unknown>;
  try {
    claims = JSON.parse(atob(authHeader.slice(7).split(".")[1]));
  } catch {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const isPlatformAdmin = claims.is_platform_admin === true;
  const permissions = Array.isArray(claims.permissions) ? (claims.permissions as string[]) : [];
  if (!isPlatformAdmin && !permissions.includes("users:invite")) {
    return new Response(JSON.stringify({ error: "Insufficient permissions" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const orgId = typeof claims.org_id === "string" ? claims.org_id : "";
  const invitedById = typeof claims.user_id === "string" ? claims.user_id : "";

  if (!orgId || !invitedById) {
    return new Response(
      JSON.stringify({ error: "Missing org or user context in token" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  let email: string, role_id: string;
  try {
    ({ email, role_id } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!email || !role_id) {
    return new Response(
      JSON.stringify({ error: "email and role_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Verify role belongs to the caller's org
  const { data: role, error: roleErr } = await supabase
    .from("roles")
    .select("id")
    .eq("id", role_id)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .single();

  if (roleErr || !role) {
    return new Response(
      JSON.stringify({ error: "Invalid role for this organization" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Block if active user with this email already exists in the org
  const { data: activeUser } = await supabase
    .from("users")
    .select("id")
    .eq("email", email)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .maybeSingle();

  if (activeUser) {
    return new Response(
      JSON.stringify({ error: "A user with this email already exists in this organization" }),
      { status: 409, headers: { "Content-Type": "application/json" } }
    );
  }

  // Revoke any existing pending invites to the same email in this org
  await supabase
    .from("invites")
    .update({ status: "revoked" })
    .eq("email", email)
    .eq("org_id", orgId)
    .eq("status", "pending");

  const token = generateToken();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

  const { data: invite, error: insertErr } = await supabase
    .from("invites")
    .insert({
      org_id: orgId,
      email,
      role_id,
      token,
      invited_by: invitedById,
      expires_at: expiresAt,
    })
    .select()
    .single();

  if (insertErr) {
    console.error("[generate-invite] insert error:", insertErr);
    return new Response(
      JSON.stringify({ error: `Failed to create invite: ${insertErr.message}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const appUrl = Deno.env.get("APP_URL") ?? "http://localhost:5173";
  const inviteUrl = `${appUrl}/accept-invite?token=${token}`;

  console.log("[generate-invite] created", {
    invite_id: invite.id,
    email,
    org_id: orgId,
    expires_at: expiresAt,
  });

  return new Response(
    JSON.stringify({ invite_id: invite.id, invite_url: inviteUrl, email }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
};

Deno.serve((req) => AuthMiddleware(req, handler));
