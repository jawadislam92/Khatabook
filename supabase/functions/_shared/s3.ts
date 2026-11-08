// Minimal S3 PutObject with AWS Signature Version 4, using WebCrypto only.

export type S3Config = { accessKey: string; secretKey: string; bucket: string; region: string };

const enc = new TextEncoder();

async function sha256Hex(data: Uint8Array | string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", typeof data === "string" ? enc.encode(data) : data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmac(key: Uint8Array | string, data: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", typeof key === "string" ? enc.encode(key) : key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data)));
}

function amzDate(d: Date): { date: string; stamp: string } {
  const iso = d.toISOString().replace(/[:-]|\.\d{3}/g, "");
  return { stamp: iso, date: iso.slice(0, 8) };
}

export async function putObject(cfg: S3Config, key: string, body: Uint8Array, contentType = "application/octet-stream"): Promise<void> {
  const host = `${cfg.bucket}.s3.${cfg.region}.amazonaws.com`;
  const { date, stamp } = amzDate(new Date());
  const payloadHash = await sha256Hex(body);
  const canonicalUri = "/" + key.split("/").map(encodeURIComponent).join("/");
  const headers: Record<string, string> = {
    "content-type": contentType,
    host,
    "x-amz-content-sha256": payloadHash,
    "x-amz-date": stamp,
  };
  const signedHeaders = Object.keys(headers).sort().join(";");
  const canonicalHeaders = Object.keys(headers).sort().map((h) => `${h}:${headers[h].trim()}\n`).join("");
  const canonicalRequest = ["PUT", canonicalUri, "", canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${date}/${cfg.region}/s3/aws4_request`;
  const stringToSign = ["AWS4-HMAC-SHA256", stamp, scope, await sha256Hex(canonicalRequest)].join("\n");
  const kDate = await hmac(`AWS4${cfg.secretKey}`, date);
  const kRegion = await hmac(kDate, cfg.region);
  const kService = await hmac(kRegion, "s3");
  const kSigning = await hmac(kService, "aws4_request");
  const signature = [...await hmac(kSigning, stringToSign)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const authorization = `AWS4-HMAC-SHA256 Credential=${cfg.accessKey}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const res = await fetch(`https://${host}${canonicalUri}`, {
    method: "PUT",
    headers: { ...headers, authorization },
    body,
  });
  if (!res.ok) throw new Error(`s3 put ${key}: ${res.status} ${await res.text()}`);
}

export async function gzip(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
