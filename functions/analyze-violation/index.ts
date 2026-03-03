import { createClient } from "jsr:@supabase/supabase-js@2";

const GEMINI_API_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent";

// Maps each violation tag to a specific analysis prompt
const VIOLATION_PROMPTS: Record<string, string> = {
  "Dog Biohazard":
    "Analyze this video clip. Is there evidence that cat waste or droppings were left without being cleaned up appropriately? Consider cat poop a brown substance that is left nearby to the cat.",
  Smoking:
    "Analyze this video clip. Is there evidence of someone smoking cigarettes, vaping, or using tobacco products in this area?",
  Trespassing:
    "Analyze this video clip. Is there evidence of someone trespassing, loitering, or being in an unauthorized or restricted area?",
  Vandalism:
    "Analyze this video clip. Is there evidence of vandalism, property damage, or graffiti occurring?",
  Tailgating:
    "Analyze this video clip. Is there evidence of tailgating — someone following closely through a secured entrance without using their own credentials?",
  "Bad Delivery":
    "Analyze this video clip. Is there evidence of a delivery person leaving a package on the ground rather than handing it off or placing it in a secure/designated location?",
  "Dog Violation":
    "Analyze this video clip frame-by-frame to identify the presence of a living dog. Distinguish clearly between a real dog and toys, statues, or other animals (such as wolves or cats). If a dog is found, describe its actions, breed (if identifiable), and the environment. If no dog is found, describe the primary subjects of the video to confirm analysis was performed. Base your confidence score on visibility, lighting, and the duration of the dog's appearance in the clip.",
  "Female":
    "Analyze this video clip. Is there a person present in the footage? If so, what is their apparent gender, and what is their approximate age? Describe their appearance, actions, and location in the frame.",
};

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    likelihood: {
      type: "integer",
      description:
        "A score from 0 to 100 representing how likely it is that the violation occurred. 0 means it definitely did not occur; 100 means it definitely did.",
    },
    summary: {
      type: "string",
      description: "A brief description of what was observed in the clip",
    },
  },
  required: ["likelihood", "summary"],
};

const _model = GEMINI_API_URL.match(/models\/([^:]+)/)?.[1] ?? "unknown";
console.log("[analyze-violation] boot", {
  model: _model,
  supportedTags: Object.keys(VIOLATION_PROMPTS),
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "(not set)",
  geminiKeySet: Boolean(Deno.env.get("GEMINI_API_KEY")),
});

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  let clip_path: string;
  let camera_uuid: string;
  let violation_tag: string;
  let timestamp: string;
  let org_id: string;

  try {
    ({ clip_path, camera_uuid, violation_tag, timestamp, org_id } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!clip_path || !camera_uuid || !violation_tag || !timestamp || !org_id) {
    return new Response(
      JSON.stringify({
        error: "Missing required fields: clip_path, camera_uuid, violation_tag, timestamp, org_id",
      }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  console.log("[analyze-violation] request", { camera_uuid, violation_tag, clip_path, timestamp });

  const prompt = VIOLATION_PROMPTS[violation_tag];
  if (!prompt) {
    return new Response(
      JSON.stringify({ error: `Unknown violation tag: ${violation_tag}` }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiApiKey) {
    return new Response(
      JSON.stringify({ error: "GEMINI_API_KEY secret not configured" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Init Supabase client using built-in service role env vars
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Download clip bytes from storage
  const { data: clipBlob, error: downloadErr } = await supabase.storage
    .from("clips")
    .download(clip_path);

  if (downloadErr || !clipBlob) {
    console.error("Storage download error:", downloadErr);
    return new Response(
      JSON.stringify({ error: `Failed to download clip: ${downloadErr?.message}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  console.log("[analyze-violation] clip downloaded", { clip_path, sizeBytes: clipBlob.size });

  // Convert Blob → ArrayBuffer → base64
  const arrayBuffer = await clipBlob.arrayBuffer();
  const uint8 = new Uint8Array(arrayBuffer);
  let binary = "";
  const chunkSize = 8192;
  for (let i = 0; i < uint8.length; i += chunkSize) {
    binary += String.fromCharCode(...uint8.subarray(i, i + chunkSize));
  }
  const base64Video = btoa(binary);

  // Build Gemini request body with the video inline
  const geminiBody = {
    contents: [
      {
        parts: [
          {
            inline_data: {
              mime_type: "video/mp4",
              data: base64Video,
            },
          },
          {
            text: `${prompt} Respond only with a JSON object matching this schema: {"likelihood": <integer 0-100>, "summary": <string>}. likelihood is an integer from 0 to 100: 0 means the violation definitely did not occur, 100 means it definitely did. Do not include a separate boolean — express your entire answer through the likelihood score.`,
          },
        ],
      },
    ],
    generationConfig: {
      response_mime_type: "application/json",
      response_schema: RESPONSE_SCHEMA,
    },
  };

  console.log("[analyze-violation] calling Gemini", { model: _model, violation_tag });

  // Call Gemini with up to 3 retries on 429 (rate limit), backing off 2 s then 4 s.
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  let geminiRes!: Response;
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await sleep(2000 * attempt);
    geminiRes = await fetch(`${GEMINI_API_URL}?key=${geminiApiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody),
    });
    if (geminiRes.status !== 429) break;
    console.warn(`Gemini 429 on attempt ${attempt + 1}, retrying...`);
  }

  if (!geminiRes.ok) {
    const errText = await geminiRes.text();
    console.error("Gemini API error:", errText);
    return new Response(
      JSON.stringify({ error: `Gemini API error: ${geminiRes.status}` }),
      { status: 502, headers: { "Content-Type": "application/json" } }
    );
  }

  const geminiJson = await geminiRes.json();

  let analysisResult: { likelihood: number; summary: string };
  try {
    const rawText = geminiJson.candidates[0].content.parts[0].text;
    analysisResult = JSON.parse(rawText);
  } catch {
    console.error("Failed to parse Gemini response:", JSON.stringify(geminiJson));
    return new Response(
      JSON.stringify({ error: "Failed to parse Gemini response" }),
      { status: 502, headers: { "Content-Type": "application/json" } }
    );
  }

  const confidence = Math.min(100, Math.max(0, Math.round(analysisResult.likelihood)));
  const isViolation = confidence > 50;

  console.log("[analyze-violation] Gemini result", {
    likelihood: confidence,
    violation: isViolation,
    summary: analysisResult.summary,
  });

  // Insert violation record into Supabase
  const { data: violation, error: insertErr } = await supabase
    .from("violations")
    .insert({
      camera_uuid,
      violation_tag,
      violation: isViolation,
      confidence,
      summary: analysisResult.summary,
      clip_path,
      timestamp,
      status: "needs_review",
      org_id,
    })
    .select()
    .single();

  if (insertErr) {
    console.error("DB insert error:", insertErr);
    return new Response(
      JSON.stringify({ error: `Failed to save violation: ${insertErr.message}` }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  console.log("[analyze-violation] done", { violation_id: violation.id, camera_uuid, violation_tag });

  return new Response(JSON.stringify(violation), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
