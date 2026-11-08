// Runs every minute (pg_cron). Sends every due alert as a push to each
// recipient's devices and writes the in app inbox row. Idempotent: a row is
// only marked sent after delivery, and retried up to five times on error.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPushes, type Push } from "../_shared/fcm.ts";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "null");
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

type Row = {
  id: string; space_id: string; kind: string; job_id: string | null; recipients: string[];
  payload: Record<string, unknown>; attempts: number;
};

function fmtTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("en-PK", { timeZone: "Asia/Karachi", weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
}

async function compose(row: Row, lang: string): Promise<{ title: string; body: string; link: string } | null> {
  const p = row.payload as Record<string, string>;
  const ur = lang === "ur";
  let customer = "";
  if (p.customer_id) {
    const { data } = await supabase.from("parties").select("name").eq("id", p.customer_id).maybeSingle();
    customer = data?.name ?? "";
  }
  const when = p.scheduled_at ? fmtTime(p.scheduled_at) : "";
  const link = row.job_id ? `/space/${row.space_id}/job/${row.job_id}` : `/space/${row.space_id}`;
  switch (row.kind) {
    case "job_assigned":
      return { title: ur ? "نیا کام" : "New job", body: ur ? `${customer}: ${p.title}، ${when}۔ تصدیق کے لیے دبائیں۔` : `${customer}: ${p.title}, ${when}. Tap to confirm.`, link };
    case "job_unconfirmed": {
      const { data } = await supabase.from("job_assignees").select("confirmed_at").eq("job_id", row.job_id!).not("confirmed_at", "is", null).limit(1);
      if (data && data.length > 0) return null; // someone confirmed, nothing to nag about
      return { title: ur ? "ابھی تک تصدیق نہیں" : "Nobody has confirmed", body: ur ? `${customer} کا ${when} والا کام ابھی تک کسی نے کنفرم نہیں کیا۔` : `The ${when} job for ${customer} has not been confirmed by anyone yet.`, link };
    }
    case "jobs_tomorrow":
      return { title: ur ? "کل کا کام" : "Tomorrow's job", body: `${customer}: ${p.title}, ${when}`, link };
    case "job_soon":
      return { title: ur ? "ایک گھنٹے میں" : "In one hour", body: `${customer}: ${p.title}${p.address ? ", " + p.address : ""}`, link };
    case "job_status": {
      let actor = "";
      if (p.actor_id) {
        const { data } = await supabase.from("profiles").select("display_name").eq("user_id", p.actor_id).maybeSingle();
        actor = data?.display_name ?? "";
      }
      const status: Record<string, [string, string]> = {
        confirmed: ["confirmed", "نے کنفرم کیا"], on_the_way: ["is on the way to", "روانہ ہیں"],
        working: ["started work at", "نے کام شروع کیا"], finished: ["finished the job at", "نے کام مکمل کیا"],
      };
      const [en, urt] = status[p.status] ?? [p.status, p.status];
      return { title: ur ? "کام کی صورتحال" : "Job update", body: ur ? `${actor} ${urt}: ${customer}` : `${actor} ${en} ${customer}`, link };
    }
    case "job_rescheduled":
      return { title: ur ? "وقت بدل گیا" : "Job moved", body: `${customer}: ${p.title}, ${when}`, link };
    case "job_cancelled":
      return { title: ur ? "کام منسوخ" : "Job cancelled", body: `${customer}: ${p.title}`, link };
    default:
      return { title: "Duebook", body: String(p.title ?? ""), link };
  }
}

Deno.serve(async (req) => {
  if (CRON_SECRET && req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  const { data: due, error } = await supabase
    .from("scheduled_notifications").select("*")
    .lte("due_at", new Date().toISOString()).is("sent_at", null).is("cancelled_at", null)
    .order("due_at").limit(200);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0, skipped = 0, failed = 0;
  for (const row of (due ?? []) as Row[]) {
    try {
      const { data: profiles } = await supabase.from("profiles").select("user_id, language").in("user_id", row.recipients);
      const { data: devices } = await supabase.from("devices").select("user_id, fcm_token").in("user_id", row.recipients);
      const pushes: Push[] = [];
      let first: { title: string; body: string; link: string } | null = null;
      for (const r of row.recipients) {
        const lang = profiles?.find((p) => p.user_id === r)?.language ?? "en";
        const msg = await compose(row, lang);
        if (!msg) { skipped++; break; }
        first ??= msg;
        for (const d of devices?.filter((d) => d.user_id === r) ?? []) {
          pushes.push({ token: d.fcm_token, title: msg.title, body: msg.body, data: { link: msg.link, kind: row.kind, job_id: row.job_id ?? "" } });
        }
      }
      if (!first) {
        await supabase.from("scheduled_notifications").update({ cancelled_at: new Date().toISOString() }).eq("id", row.id);
        continue;
      }
      if (serviceAccount) {
        const dead = await sendPushes(serviceAccount, pushes);
        if (dead.length) await supabase.from("devices").delete().in("fcm_token", dead);
      }
      await supabase.rpc("mark_notification_sent", { p_id: row.id, p_title: first.title, p_body: first.body, p_deep_link: first.link });
      sent++;
    } catch (e) {
      failed++;
      await supabase.rpc("mark_notification_sent", { p_id: row.id, p_title: "", p_body: "", p_deep_link: "", p_error: String(e).slice(0, 500) });
    }
  }
  return Response.json({ sent, skipped, failed, checked: due?.length ?? 0 });
});
