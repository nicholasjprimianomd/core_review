/**
 * Study progress sync: verifies the user's JWT, then reads/writes progress via PostgREST.
 *
 * Supabase project resolution (must match the Flutter app JWT / anon key):
 *   1) process.env SUPABASE_* / NEXT_PUBLIC_SUPABASE_*
 *   2) api/_build_supabase_config.js (emitted by tool/build_web_for_vercel.py from the same
 *      env vars used for flutter --dart-define)
 *   3) hardcoded defaults from lib/config/app_config.dart
 *
 * Tables tried in order: core_review_study_progress, then user_progress (see supabase/schema.sql).
 *
 * Optional: SUPABASE_SERVICE_ROLE_KEY for legacy user_metadata merge via admin API.
 */

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Refresh-Token, Accept',
  );
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

/** Repo schema used `user_progress`; app code often uses `core_review_study_progress`. */
const PROGRESS_TABLE_CANDIDATES = ['core_review_study_progress', 'user_progress'];

async function selectProgressRow(supabaseUrl, restHeaders, userId) {
  for (const table of PROGRESS_TABLE_CANDIDATES) {
    try {
      const sel = await fetch(
        `${supabaseUrl}/rest/v1/${table}?user_id=eq.${encodeURIComponent(userId)}&select=progress`,
        { headers: restHeaders },
      );
      if (!sel.ok) {
        continue;
      }
      const rows = await sel.json();
      const tableProgress =
        rows[0]?.progress && typeof rows[0].progress === 'object'
          ? rows[0].progress
          : { answers: {} };
      return { table, tableProgress };
    } catch (_) {}
  }
  return { table: null, tableProgress: { answers: {} } };
}

async function upsertProgressRow(supabaseUrl, restHeaders, userId, row, preferredTable) {
  const order = preferredTable
    ? [preferredTable, ...PROGRESS_TABLE_CANDIDATES.filter((t) => t !== preferredTable)]
    : PROGRESS_TABLE_CANDIDATES.slice();
  let lastDetail = '';
  for (const table of order) {
    const upsertUrl = `${supabaseUrl}/rest/v1/${table}?on_conflict=user_id`;
    const up = await fetch(upsertUrl, {
      method: 'POST',
      headers: {
        ...restHeaders,
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify(row),
    });
    if (up.ok) {
      return { ok: true };
    }
    lastDetail = await up.text();
  }
  return { ok: false, detail: lastDetail };
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

// Written by tool/build_web_for_vercel.py so this API uses the *same* Supabase project as the Flutter bundle.
let supabaseBuildConfig = null;
try {
  supabaseBuildConfig = require('./_build_supabase_config.js');
} catch (_) {
  supabaseBuildConfig = null;
}

// Fallbacks match lib/config/app_config.dart (already public in the client).
const DEFAULT_SUPABASE_URL = 'https://szerwpvldtnamhfpqmih.supabase.co';
const DEFAULT_SUPABASE_ANON_KEY =
  'sb_publishable_gmJyumfHSnoOTqpMkVS-qw_A6axiU62';

function resolveSupabaseConfig() {
  const supabaseUrl = `${process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || supabaseBuildConfig?.url || DEFAULT_SUPABASE_URL}`.replace(
    /\/$/,
    '',
  );
  const serviceKey = `${process.env.SUPABASE_SERVICE_ROLE_KEY || ''}`.trim();
  const anonKey = `${process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || supabaseBuildConfig?.anonKey || DEFAULT_SUPABASE_ANON_KEY}`.trim();
  return { supabaseUrl, serviceKey, anonKey };
}

module.exports = async (req, res) => {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  const { supabaseUrl, serviceKey, anonKey } = resolveSupabaseConfig();
  const apiKeyForAuth = serviceKey || anonKey;

  if (!supabaseUrl || !apiKeyForAuth) {
    res.status(503).json({
      error:
        'Study progress API not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY on Vercel.',
    });
    return;
  }

  const useServiceRole = Boolean(serviceKey);

  const authHeader = `${req.headers.authorization || ''}`;
  const refreshToken = `${req.headers['x-refresh-token'] || ''}`;
  const m = authHeader.match(/^Bearer\s+(\S+)/i);
  let userJwt = m ? m[1] : '';

  let userId = null;
  if (userJwt) {
    const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: apiKeyForAuth,
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
          apikey: apiKeyForAuth,
          Authorization: `Bearer ${apiKeyForAuth}`,
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

  const restHeaders = useServiceRole
    ? {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      }
    : {
        apikey: anonKey,
        Authorization: `Bearer ${userJwt}`,
        'Content-Type': 'application/json',
      };

  if (req.method === 'GET') {
    const { tableProgress } = await selectProgressRow(supabaseUrl, restHeaders, userId);
    const metaProgress = useServiceRole
      ? await readMetaProgress(supabaseUrl, serviceKey, userId)
      : null;
    const progress = mergeProgress(tableProgress, metaProgress || { answers: {} });
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

    const { tableProgress, table: preferredTable } = await selectProgressRow(
      supabaseUrl,
      restHeaders,
      userId,
    );
    const metaProgress = useServiceRole
      ? await readMetaProgress(supabaseUrl, serviceKey, userId)
      : null;
    const merged = mergeProgress(
      mergeProgress(tableProgress, metaProgress || { answers: {} }),
      incoming,
    );

    const row = {
      user_id: userId,
      progress: merged,
      updated_at: new Date().toISOString(),
    };

    const up = await upsertProgressRow(supabaseUrl, restHeaders, userId, row, preferredTable);

    if (!up.ok) {
      res.status(502).json({ error: 'Failed to save progress.', detail: up.detail });
      return;
    }

    res.status(204).end();
    return;
  }

  res.status(405).json({ error: 'Use GET or PUT.' });
};
