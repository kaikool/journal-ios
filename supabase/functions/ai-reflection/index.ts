// Supabase Edge Function: ai-reflection
// Handles AI analysis and trader reflection securely on server-side without leaking API keys to client.
// Conforms to Rule R005 (No secrets in iOS binary).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const SYSTEM_PROMPT = `You are the reflection layer of a trader's journal.
You see only the trader's own recorded data — trades, stats, and notes. Ground every
statement in those numbers; never invent trades, prices, or market context you weren't given.
Be direct and specific like a good trading coach: name the behavior, cite the numbers,
say what to keep and what to fix. No platitudes, no disclaimers about trading being risky —
the trader knows. Keep it tight.`;

interface RequestBody {
  action: "ask" | "critique" | "recap";
  prompt?: string;
  scopeSummary?: {
    totalTrades: number;
    winRate: number;
    profitFactor: number | null;
    netPnl: number;
    maxDrawdownPct: number | null;
    edgeScore: number | null;
  };
  tradeData?: Record<string, unknown>;
}

serve(async (req: Request) => {
  // CORS Headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body: RequestBody = await req.json();
    const apiKey = Deno.env.get("OPENAI_API_KEY") || Deno.env.get("ANTHROPIC_API_KEY");

    if (!apiKey) {
      return new Response(
        JSON.stringify({
          error: "AI provider key not configured in Supabase environment secrets.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Construct grounded prompt
    let userPrompt = "";
    if (body.action === "ask") {
      userPrompt = `User question: "${body.prompt ?? ""}"\n\nTrader's Current Performance Context:\n${JSON.stringify(body.scopeSummary, null, 2)}`;
    } else if (body.action === "critique") {
      userPrompt = `Please critique this specific trade performance and execution:\n${JSON.stringify(body.tradeData, null, 2)}`;
    } else if (body.action === "recap") {
      userPrompt = `Generate a direct, actionable performance recap based on these period stats:\n${JSON.stringify(body.scopeSummary, null, 2)}`;
    }

    // Call OpenAI endpoint
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.2,
        max_tokens: 1000,
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      return new Response(
        JSON.stringify({ error: `AI Provider Error: ${response.status}`, details: errText }),
        {
          status: response.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const aiData = await response.json();
    const replyText = aiData.choices?.[0]?.message?.content ?? "No response generated.";

    return new Response(
      JSON.stringify({
        action: body.action,
        reflection: replyText,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: errorMsg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
