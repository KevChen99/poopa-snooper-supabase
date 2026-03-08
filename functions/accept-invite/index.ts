import { createClient } from "jsr:@supabase/supabase-js@2";
import { hashToken } from "../_shared/crypto.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: JSON_HEADERS,
    });
  }

  let token: string, password: string, display_name: string;
  try {
    ({ token, password, display_name = "" } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  if (!token || !password) {
    return new Response(
      JSON.stringify({ error: "token and password are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );  
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Step 1: Validate the invite token
  const tokenHash = await hashToken(token);
  const { data: invites } = await supabase
    .from("invites")
    .select("*")
    .eq("token", tokenHash)
    .eq("status", "pending");

  if (!invites || invites.length === 0) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired invite token" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const invite = invites[0];

  if (new Date(invite.expires_at) < new Date()) {
    await supabase
      .from("invites")
      .update({ status: "expired" })
      .eq("id", invite.id);
    return new Response(
      JSON.stringify({ error: "Invite token has expired" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const { email, org_id, role_id } = invite;

  // Step 2: Check for active user collision
  const { data: activeUser } = await supabase
    .from("users")
    .select("id")
    .eq("email", email)
    .eq("org_id", org_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (activeUser) {
    return new Response(
      JSON.stringify({ error: "Email already active in this organization" }),
      { status: 409, headers: { "Content-Type": "application/json" } }
    );
  }

  // Step 3: Identity-preserving rename for soft-deleted users
  const { data: deletedUsers } = await supabase
    .from("users")
    .select("id, auth_id")
    .eq("email", email)
    .eq("org_id", org_id)
    .not("deleted_at", "is", null);

  for (const deletedUser of deletedUsers ?? []) {
    const dummyEmail = `deleted_${deletedUser.id}_${email}`;
    try {
      await supabase.auth.admin.updateUserById(deletedUser.auth_id, {
        email: dummyEmail,
      });
    } catch (err) {
      console.warn(
        `[accept-invite] Failed to rename auth email for deleted user ${deletedUser.auth_id}:`,
        err
      );
    }
  }

  // Step 4: Revoke other stale pending invites to the same email in this org
  const { data: staleInvites } = await supabase
    .from("invites")
    .select("id")
    .eq("email", email)
    .eq("org_id", org_id)
    .eq("status", "pending")
    .neq("id", invite.id);

  for (const stale of staleInvites ?? []) {
    await supabase
      .from("invites")
      .update({ status: "revoked" })
      .eq("id", stale.id);
  }

  // Step 5: Create new Supabase Auth user
  const { data: authData, error: authErr } =
    await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

  if (authErr || !authData.user) {
    console.error("[accept-invite] auth.admin.createUser error:", authErr);
    return new Response(
      JSON.stringify({ error: `Failed to create auth user: ${authErr?.message}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const newAuthId = authData.user.id;

  // Step 6: Create application user row
  const { data: roleData } = await supabase
    .from("roles")
    .select("name")
    .eq("id", role_id)
    .maybeSingle();

  const roleName = roleData?.name ?? "Unknown";

  const { data: newUser, error: userInsertErr } = await supabase
    .from("users")
    .insert({
      auth_id: newAuthId,
      org_id,
      role_id,
      email,
      display_name: display_name || email,
    })
    .select()
    .single();

  if (userInsertErr || !newUser) {
    console.error("[accept-invite] users insert error:", userInsertErr);
    // Compensate: remove the orphaned auth user so the invite can be retried
    await supabase.auth.admin.deleteUser(newAuthId);
    return new Response(
      JSON.stringify({ error: `Failed to create user: ${userInsertErr?.message}` }),
      { status: 500, headers: JSON_HEADERS }
    );
  }

  // Step 7: Mark invite as accepted
  await supabase
    .from("invites")
    .update({ status: "accepted", accepted_at: new Date().toISOString() })
    .eq("id", invite.id);

  // Step 8: Audit log (system action — no authenticated actor)
  try {
    await supabase.from("audit_logs").insert({
      org_id,
      actor_id: null,
      action: "user.invite_accepted",
      resource_type: "user",
      resource_id: newUser.id,
      details: {
        actor_email: email,
        actor_display_name: display_name || email,
        actor_role_name: roleName,
        invite_id: invite.id,
        invited_by: invite.invited_by,
      },
      ip_address: req.headers.get("x-forwarded-for") ?? null,
      user_agent: req.headers.get("user-agent") ?? null,
    });
  } catch (err) {
    console.error("[accept-invite] audit log failed:", err);
    // Non-fatal — don't fail the request
  }

  return new Response(JSON.stringify({ user: newUser }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
