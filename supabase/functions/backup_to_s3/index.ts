// Nightly backup: every public table and the auth user list, as gzip
// compressed JSON lines, written to the owner's S3 bucket under
// duebook/<project ref>/<YYYY-MM-DD>/<table>.json.gz. Gated by CRON_SECRET.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { gzip, putObject, type S3Config } from "../_shared/s3.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const supabase = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const s3: S3Config = {
  accessKey: Deno.env.get("BACKUP_S3_ACCESS_KEY") ?? "",
  secretKey: Deno.env.get("BACKUP_S3_SECRET_KEY") ?? "",
  bucket: Deno.env.get("BACKUP_S3_BUCKET") ?? "",
  region: Deno.env.get("BACKUP_S3_REGION") ?? "ap-south-1",
};
const projectRef = new URL(url).hostname.split(".")[0];

async function dumpTable(table: string): Promise<{ rows: number; bytes: number }> {
  const lines: string[] = [];
  const page = 1000;
  for (let from = 0; ; from += page) {
    const { data, error } = await supabase.from(table).select("*").range(from, from + page - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    for (const r of data ?? []) lines.push(JSON.stringify(r));
    if (!data || data.length < page) break;
  }
  const body = await gzip(new TextEncoder().encode(lines.join("\n") + (lines.length ? "\n" : "")));
  const day = new Date().toISOString().slice(0, 10);
  await putObject(s3, `duebook/${projectRef}/${day}/${table}.json.gz`, body, "application/gzip");
  return { rows: lines.length, bytes: body.byteLength };
}

async function dumpUsers(): Promise<{ rows: number; bytes: number }> {
  const lines: string[] = [];
  for (let pageNo = 1; ; pageNo++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page: pageNo, perPage: 1000 });
    if (error) throw new Error(`auth users: ${error.message}`);
    for (const u of data.users) {
      lines.push(JSON.stringify({ id: u.id, email: u.email, phone: u.phone, created_at: u.created_at, user_metadata: u.user_metadata }));
    }
    if (data.users.length < 1000) break;
  }
  const body = await gzip(new TextEncoder().encode(lines.join("\n") + (lines.length ? "\n" : "")));
  const day = new Date().toISOString().slice(0, 10);
  await putObject(s3, `duebook/${projectRef}/${day}/auth_users.json.gz`, body, "application/gzip");
  return { rows: lines.length, bytes: body.byteLength };
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  if (!s3.accessKey || !s3.secretKey || !s3.bucket) {
    return new Response("S3 secrets are not configured", { status: 500 });
  }
  const { data: tables, error } = await supabase.rpc("backup_table_names");
  if (error) return new Response(error.message, { status: 500 });
  const result: Record<string, { rows: number; bytes: number } | string> = {};
  let failed = 0;
  for (const t of (tables as { table_name: string }[]).map((r) => r.table_name)) {
    try {
      result[t] = await dumpTable(t);
    } catch (e) {
      failed++;
      result[t] = String(e).slice(0, 300);
    }
  }
  try {
    result.auth_users = await dumpUsers();
  } catch (e) {
    failed++;
    result.auth_users = String(e).slice(0, 300);
  }
  return Response.json({ ok: failed === 0, failed, bucket: s3.bucket, prefix: `duebook/${projectRef}/`, result }, { status: failed ? 500 : 200 });
});
