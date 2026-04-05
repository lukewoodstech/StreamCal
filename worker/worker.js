/**
 * StreamCal AI Backend — Cloudflare Worker
 *
 * Deploy at: https://dash.cloudflare.com → Workers & Pages → Create Worker
 *
 * Set these environment variables in the Cloudflare dashboard:
 *   ANTHROPIC_API_KEY    — your Anthropic API key (sk-ant-...)
 *   REVENUECAT_SECRET_KEY — RevenueCat secret key (from RC dashboard → API Keys → Secret keys)
 *
 * After deployment, copy your Worker URL into ClaudeService.swift → workerURL
 */

export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response('Invalid JSON', { status: 400 });
    }

    const { prompt, customerID } = body;
    if (!prompt || !customerID) {
      return new Response('Bad request: prompt and customerID required', { status: 400 });
    }

    // Verify Pro entitlement via RevenueCat REST API
    let isPro = false;
    try {
      const rcRes = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(customerID)}`,
        { headers: { Authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}` } }
      );
      if (rcRes.ok) {
        const rcData = await rcRes.json();
        const proEntitlement = rcData.subscriber?.entitlements?.pro;
        if (proEntitlement) {
          // Active if no expiry date (lifetime) or expiry is in the future
          isPro = !proEntitlement.expires_date ||
            new Date(proEntitlement.expires_date) > new Date();
        }
      }
    } catch {
      return new Response('Failed to verify subscription', { status: 502 });
    }

    if (!isPro) {
      return new Response('Pro subscription required', { status: 403 });
    }

    // Forward prompt to Claude
    try {
      const aiRes = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 256,
          messages: [{ role: 'user', content: prompt }],
        }),
      });

      if (!aiRes.ok) {
        return new Response('AI request failed', { status: 502 });
      }

      const aiData = await aiRes.json();
      const text = aiData.content?.[0]?.text ?? '';
      return new Response(JSON.stringify({ text }), {
        headers: { 'content-type': 'application/json' },
      });
    } catch {
      return new Response('AI request failed', { status: 502 });
    }
  },
};
