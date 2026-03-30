/**
 * Authoritative study progress sync: verifies the user's JWT, then reads/writes
 * `core_review_study_progress` with the service role (bypasses RLS + flaky client PostgREST).
 *
 * Vercel env (required for this route):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY  (Settings -> API -> service_role; never ship to the client)
 */

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function parseBody(body) {
  if (body == null) {
    return {};
  }
  if (typeof body === 'string') {
    try {
      return JSON.parse(body);
    } catch (_) {
      return {};
    }
  }
  if (typeof body === 'object') {
    return body;
  }
  return {};
}

function mergeAnswerMaps(a, b) {
  const aa = a && typeof a === 'object' ? a : {};
  const bb = b && typeof b === 'object' ? b : {};
  const keys = new Set([...Object.keys(aa), ...Object.keys(bb)]);
  const merged = {};
  for (const k of keys) {
    const pa = aa[k];
    const pb = bb[k];
    if (!pa) {
      merged[k] = pb;
      continue;
    }
    if (!pb) {
      merged[k] = pa;
      continue;
    }
    const ta = Date.parse(pa.answeredAt || '1970-01-01') || 0;
    const tb = Date.parse(pb.answeredAt || '1970-01-01') || 0;
    merged[k] = ta >= tb ? pa : pb;
  }
  return merged;
}

function mergeProgress(tableProg, otherProg) {
  const t = tableProg && typeof tableProg === 'object' ? tableProg : { answers: {} };
  const o = otherProg && typeof otherProg === 'object' ? otherProg : { answers: {} };
  const answers = mergeAnswerMaps(t.answers || {}, o.answers || {});
  return {
    answers,
    lastVisitedQuestionId: o.lastVisitedQuestionId || t.lastVisitedQuestionId || null,
    updatedAt: o.updatedAt || t.updatedAt || new Date().toISOString(),
  };
}

async function readTableProgress(supabaseUrl, restHeaders, userId) {
  let tableProgress = { answers: {} };
  try {
    const sel = await fetch(
      `${supabaseUrl}/rest/v1/core_review_study_progress?user_id=eq.${encodeURIComponent(userId)}&select=progress`,
      { headers: restHeaders },
    );
    if (sel.ok) {
      const rows = await sel.json();
      if (rows[0]?.progress && typeof rows[0].progress === 'object') {
        tableProgress = rows[0].progress;
      }
    }
  } catch (_) {}
  return tableProgress;
}

async function readMetaProgress(supabaseUrl, serviceKey, userId) {
  let metaProgress = null;
  try {
    const adminRes = await fetch(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });
    if (adminRes.ok) {
      const adminData = await adminRes.json();
      const u = adminData.user || adminData;
      const um = u?.user_metadata;
      if (um?.core_review_progress && typeof um.core_review_progress === 'object') {
        metaProgress = um.core_review_progress;
      }
    }
  } catch (_) {}
  return metaProgress;
}

module.exports = async (req, res) => {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  const supabaseUrl = `${process.env.SUPABASE_URL || ''}`.replace(/\/$/, '');
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceKey) {
    res.status(503).json({
      error:
        'Study progress API not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on Vercel.',
    });
    return;
  }

  const authHeader = `${req.headers.authorization || ''}`;
  const refreshToken = `${req.headers['x-refresh-token'] || ''}`;
  const m = authHeader.match(/^Bearer\s+(\S+)/i);
  let userJwt = m ? m[1] : '';

  let userId = null;
  if (userJwt) {
    const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${userJwt}`,
      },
    });

    if (userRes.ok) {
      const userPayload = await userRes.json();
      const sessionUser = userPayload.user || userPayload;
      userId = sessionUser.id;
    }
  }

  if (!userId && refreshToken) {
    const refreshRes = await fetch(
      `${supabaseUrl}/auth/v1/token?grant_type=refresh_token`,
      {
        method: 'POST',
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      },
    );

    if (refreshRes.ok) {
      const refreshed = await refreshRes.json();
      const sessionUser = refreshed.user || refreshed.session?.user;
      userJwt = refreshed.access_token || refreshed.session?.access_token || userJwt;
      userId = sessionUser?.id || null;
    }
  }

  if (!userId) {
    res.status(401).json({
      error: 'Invalid or expired session.',
      detail: 'Could not read user id from access token or refresh token.',
    });
    return;
  }

  const restHeaders = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    'Content-Type': 'application/json',
  };

  if (req.method === 'GET') {
    const tableProgress = await readTableProgress(supabaseUrl, restHeaders, userId);
    const metaProgress = await readMetaProgress(supabaseUrl, serviceKey, userId);
    const progress = mergeProgress(tableProgress, metaProgress);
    res.status(200).json({ progress });
    return;
  }

  if (req.method === 'PUT' || req.method === 'POST') {
    const body = parseBody(req.body);
    const incoming = body.progress;
    if (!incoming || typeof incoming !== 'object') {
      res.status(400).json({ error: 'JSON body must include a "progress" object.' });
      return;
    }

    const tableProgress = await readTableProgress(supabaseUrl, restHeaders, userId);
    const metaProgress = await readMetaProgress(supabaseUrl, serviceKey, userId);
    const merged = mergeProgress(mergeProgress(tableProgress, metaProgress), incoming);

    const row = {
      user_id: userId,
      progress: merged,
      updated_at: new Date().toISOString(),
    };

    const upsertUrl = `${supabaseUrl}/rest/v1/core_review_study_progress?on_conflict=user_id`;
    const up = await fetch(upsertUrl, {
      method: 'POST',
      headers: {
        ...restHeaders,
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify(row),
    });

    if (!up.ok) {
      const detail = await up.text();
      res.status(502).json({ error: 'Failed to save progress.', detail });
      return;
    }

    res.status(204).end();
    return;
  }

  res.status(405).json({ error: 'Use GET or PUT.' });
};
