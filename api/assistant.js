const OPENI_BASE_URL = 'https://openi.nlm.nih.gov';

function resolveModel() {
  return process.env.OPENAI_MODEL || 'gpt-5.4-nano';
}

/** Reasoning block adds latency; skip for nano/mini-style models and non-reasoning endpoints. */
function openAiReasoningPayload(model) {
  if (/nano|mini/i.test(model) && !/^o/i.test(model)) {
    return {};
  }
  if (/^gpt-5|^o3|^o4/i.test(model)) {
    return { reasoning: { effort: 'low' } };
  }
  return {};
}

const SYSTEM_PROMPT = `
You are the Core Review study assistant for radiology board-review content.

Follow these rules:
- Use only the current question context and the user's request.
- Do not search, cite, or refer to other textbook questions, chapters, or sections.
- Give concise but helpful educational explanations that focus on imaging findings, pathology patterns, and differential clues.
- If answer reveal is not allowed, do not reveal the correct option, do not rank the choices, and do not state which answer is right. Stay in hint mode and focus on concepts, image patterns, and reasoning strategies.
- If answer reveal is allowed, you may explain why the correct answer is right and why distractors are less likely.
- Always provide search terms suited for web radiology IMAGE search (e.g. Google Images style): modality + key finding or disease name.
- searchTerms: 2 to 4 aggregate phrases (overall question), each under 8 words.
- choiceImageQueries: one object per answer choice key present in study context (e.g. A, B, C). Each object has choiceKey matching that key exactly, and queries: 1 to 2 short phrases to find EXAMPLE IMAGES for what THAT option describes—the correct option and every distractor must each get their own targeted imaging phrases (same structure in study mode; do not label which option is correct).
- Do not claim to have inspected any image unless image content was actually provided.
- If the supplied context does not support a claim, say so plainly.
- This is for study support, not patient care.

Return a JSON object with exactly these keys:
- "answer": string
- "searchTerms": string[]
- "choiceImageQueries": array of { "choiceKey": string, "queries": string[] }
`;

module.exports = async (req, res) => {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Only POST is supported.' });
    return;
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    res.status(500).json({
      error: 'The server is missing OPENAI_API_KEY.',
    });
    return;
  }

  const requestBody = parseBody(req.body);
  const userPrompt = `${requestBody.userPrompt || ''}`.trim();
  const studyContext = requestBody.studyContext || {};
  const includeAnswer = requestBody.includeAnswer !== false;
  const includeWebImages = requestBody.includeWebImages === true;
  const requestedSearchTerms = normalizeSearchTerms(requestBody.searchTerms);

  if (!includeAnswer && !includeWebImages) {
    res.status(400).json({
      error: 'At least one assistant output must be requested.',
    });
    return;
  }

  if (includeAnswer && !userPrompt) {
    res.status(400).json({ error: 'userPrompt is required.' });
    return;
  }

  try {
    let answer = '';
    let searchTerms = requestedSearchTerms;
    let assistantPayload = null;

    if (includeAnswer) {
      const prompt = buildUserPrompt({ userPrompt, studyContext });
      const model = resolveModel();
      const isExplainAllChoices =
          `${studyContext?.assistantTask || ''}`.trim() === 'explainAllChoices';
      const maxOutputTokens = isExplainAllChoices ? 2200 : 800;
      const openAiResponse = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          ...openAiReasoningPayload(model),
          max_output_tokens: maxOutputTokens,
          text: {
            format: {
              type: 'json_schema',
              name: 'core_review_assistant_response',
              strict: true,
              schema: {
                type: 'object',
                additionalProperties: false,
                properties: {
                  answer: {
                    type: 'string',
                  },
                  searchTerms: {
                    type: 'array',
                    items: {
                      type: 'string',
                    },
                  },
                  choiceImageQueries: {
                    type: 'array',
                    items: {
                      type: 'object',
                      additionalProperties: false,
                      properties: {
                        choiceKey: { type: 'string' },
                        queries: {
                          type: 'array',
                          items: { type: 'string' },
                        },
                      },
                      required: ['choiceKey', 'queries'],
                    },
                  },
                },
                required: ['answer', 'searchTerms', 'choiceImageQueries'],
              },
            },
          },
          input: [
            {
              role: 'system',
              content: [{ type: 'input_text', text: SYSTEM_PROMPT }],
            },
            {
              role: 'user',
              content: [{ type: 'input_text', text: prompt }],
            },
          ],
        }),
      });

      const rawResponseText = await openAiResponse.text();
      const openAiPayload = parseJsonSafely(rawResponseText);

      if (!openAiResponse.ok) {
        res.status(openAiResponse.status).json({
          error:
              openAiPayload?.error?.message ||
              'The OpenAI request failed unexpectedly.',
        });
        return;
      }

      const outputText = extractOutputText(openAiPayload);
      if (!outputText) {
        res.status(502).json({
          error: 'The assistant returned an empty response.',
        });
        return;
      }

      assistantPayload =
        parseJsonSafely(outputText) || parseJsonObjectFromText(outputText);
      if (!assistantPayload || typeof assistantPayload !== 'object') {
        res.status(502).json({
          error: 'The assistant returned invalid JSON.',
        });
        return;
      }

      answer = normalizeAnswer(assistantPayload.answer);
      searchTerms = normalizeSearchTerms(assistantPayload.searchTerms);
    }

    const choiceImageQueries = includeAnswer
      ? normalizeChoiceImageQueries(assistantPayload?.choiceImageQueries)
      : [];

    const webImages = includeWebImages
      ? await fetchWebImages({
          req,
          searchTerms,
          choiceImageQueries,
          studyContext,
        })
      : [];

    res.status(200).json({
      answer,
      searchTerms,
      webImages,
      model: includeAnswer ? resolveModel() : '',
    });
  } catch (error) {
    res.status(500).json({
      error:
          error instanceof Error
            ? error.message
            : 'The assistant request failed.',
    });
  }
};

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function parseBody(body) {
  if (!body) {
    return {};
  }

  if (typeof body === 'string') {
    return parseJsonSafely(body) || {};
  }

  if (typeof body === 'object') {
    return body;
  }

  return {};
}

function buildUserPrompt({ userPrompt, studyContext }) {
  const task = `${studyContext?.assistantTask || ''}`.trim();
  const taskNote =
      task === 'explainAllChoices'
          ? [
            '',
            'Task note: The user is asking for every answer choice to be explained.',
            'In the "answer" string, use clear labeled sections per choice (e.g. "A:", "B:") that a resident can scan quickly.',
            'Keep searchTerms and choiceImageQueries complete per the system rules.',
            '',
          ].join('\n')
          : '';

  return [
    'Use only the following current question context and user request.',
    'Do not refer to other textbook content.',
    'Respond in JSON.',
    '',
    'User request:',
    userPrompt,
    taskNote,
    '',
    'Study context JSON:',
    JSON.stringify(studyContext, null, 2),
  ].join('\n');
}

function extractOutputText(payload) {
  if (!payload || typeof payload !== 'object') {
    return '';
  }

  if (typeof payload.output_text === 'string' && payload.output_text.trim()) {
    return payload.output_text.trim();
  }

  const output = Array.isArray(payload.output) ? payload.output : [];
  const parts = [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];
    for (const block of content) {
      if (block?.type === 'output_text' && typeof block.text === 'string') {
        parts.push(block.text);
      }
    }
  }

  return parts.join('\n').trim();
}

function normalizeAnswer(answer) {
  if (typeof answer !== 'string') {
    return 'No answer was returned.';
  }

  const trimmed = answer.trim();
  return trimmed || 'No answer was returned.';
}

function normalizeSearchTerms(searchTerms) {
  if (!Array.isArray(searchTerms)) {
    return [];
  }

  return searchTerms
      .filter((term) => typeof term === 'string')
      .map((term) => term.trim())
      .filter(Boolean)
      .slice(0, 4);
}

function normalizeChoiceImageQueries(rows) {
  if (!Array.isArray(rows)) {
    return [];
  }
  return rows
      .filter((r) => r && typeof r === 'object')
      .map((r) => ({
        choiceKey: `${r.choiceKey || ''}`.trim(),
        queries: Array.isArray(r.queries)
            ? r.queries
                .filter((x) => typeof x === 'string')
                .map((q) => q.trim())
                .filter(Boolean)
            : [],
      }))
      .filter((r) => r.choiceKey && r.queries.length > 0);
}

function resolveChoiceKey(raw, choices) {
  if (!choices || typeof choices !== 'object') {
    return null;
  }
  const r = `${raw || ''}`.trim();
  if (choices[r]) {
    return r;
  }
  const upper = r.toUpperCase();
  if (choices[upper]) {
    return upper;
  }
  const lower = r.toLowerCase();
  for (const k of Object.keys(choices)) {
    if (k.toLowerCase() === lower) {
      return k;
    }
  }
  return null;
}

function buildPerChoiceImageJobs({ choiceImageQueries, studyContext, searchTerms }) {
  const choices =
    studyContext?.choices && typeof studyContext.choices === 'object'
      ? studyContext.choices
      : {};
  const keys = Object.keys(choices).sort((a, b) =>
    a.localeCompare(b, undefined, { numeric: true }),
  );
  const byKey = new Map();
  for (const row of choiceImageQueries) {
    const k = resolveChoiceKey(row.choiceKey, choices);
    if (!k) {
      continue;
    }
    const q = (row.queries || []).map(sanitizeImageQuery).find(Boolean);
    if (q) {
      byKey.set(k, q);
    }
  }
  const jobs = [];
  for (const k of keys) {
    let q = byKey.get(k);
    if (!q) {
      const text = `${choices[k] || ''}`.trim();
      q = sanitizeImageQuery(
          text ? `${text} radiology imaging` : searchTerms[0] || '',
      );
    }
    if (!q && searchTerms.length) {
      q = sanitizeImageQuery(searchTerms[0]);
    }
    if (q) {
      jobs.push({ choiceKey: k, query: q, choiceText: choices[k] || '' });
    }
  }
  return jobs;
}

function shouldProxyImageUrl(urlStr) {
  try {
    const h = new URL(urlStr).hostname;
    return (
      h === 'openi.nlm.nih.gov' ||
      h.endsWith('.googleusercontent.com') ||
      h.endsWith('.gstatic.com')
    );
  } catch (_) {
    return false;
  }
}

function safeImageUrlForClient(req, urlStr) {
  if (!urlStr) {
    return '';
  }
  return shouldProxyImageUrl(urlStr)
    ? buildImageProxyUrl(req, urlStr)
    : urlStr;
}

function truncateText(s, n) {
  const t = `${s || ''}`.replace(/\s+/g, ' ').trim();
  if (t.length <= n) {
    return t;
  }
  return `${t.slice(0, n - 1)}…`;
}

async function fetchGoogleFirstImageItem(apiKey, cx, query) {
  try {
    const u = new URL('https://www.googleapis.com/customsearch/v1');
    u.searchParams.set('key', apiKey);
    u.searchParams.set('cx', cx);
    u.searchParams.set('q', query);
    u.searchParams.set('searchType', 'image');
    u.searchParams.set('num', '5');
    u.searchParams.set('safe', 'active');
    const r = await fetch(u);
    if (!r.ok) {
      return null;
    }
    const payload = await r.json();
    const items = Array.isArray(payload?.items) ? payload.items : [];
    for (const it of items) {
      if (it?.link || it?.image?.thumbnailLink) {
        return it;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

function mapGoogleImageResult(req, item, job) {
  const link = `${item?.link || ''}`.trim();
  const thumb = `${item?.image?.thumbnailLink || ''}`.trim();
  const full = link || thumb;
  const preview = thumb || link;
  if (!full) {
    return null;
  }
  let pageUrl = `${item?.image?.contextLink || item?.displayLink || ''}`.trim();
  if (pageUrl && !pageUrl.startsWith('http')) {
    pageUrl = `https://${pageUrl}`;
  }
  const choiceTextShort = truncateText(job.choiceText, 72);
  return {
    title: `Option ${job.choiceKey}${
      choiceTextShort ? ` — ${choiceTextShort}` : ''
    }`,
    caption: `Image search: ${job.query}`,
    imageUrl: safeImageUrlForClient(req, full),
    thumbnailUrl: safeImageUrlForClient(req, preview),
    sourceUrl: pageUrl,
    sourceLabel: 'Google Images',
    query: job.query,
    choiceKey: job.choiceKey,
    choiceTextSnippet: truncateText(job.choiceText, 200),
  };
}

async function fetchOpeniSingleResult(req, job) {
  try {
    const url = new URL('/search', OPENI_BASE_URL);
    url.searchParams.set('query', job.query);
    url.searchParams.set('it', 'xg');
    url.searchParams.set('m', '1');
    url.searchParams.set('n', '3');
    const response = await fetch(url);
    if (!response.ok) {
      return null;
    }
    const payload = await response.json();
    const items = Array.isArray(payload?.list) ? payload.list : [];
    for (const item of items) {
      const m = mapOpeniResult(req, item, job.query, job);
      if (m) {
        return m;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

async function fetchWebImages({ req, searchTerms, choiceImageQueries, studyContext }) {
  const googleKey = process.env.GOOGLE_CUSTOM_SEARCH_API_KEY;
  const googleCx = process.env.GOOGLE_CUSTOM_SEARCH_ENGINE_ID;
  const jobs = buildPerChoiceImageJobs({
    choiceImageQueries,
    studyContext,
    searchTerms,
  });
  if (jobs.length === 0) {
    return [];
  }

  const out = [];
  const seen = new Set();
  const maxTotal = 10;

  for (const job of jobs) {
    if (out.length >= maxTotal) {
      break;
    }
    let mapped = null;
    if (googleKey && googleCx) {
      const gItem = await fetchGoogleFirstImageItem(
          googleKey,
          googleCx,
          job.query,
      );
      if (gItem) {
        mapped = mapGoogleImageResult(req, gItem, job);
      }
    }
    if (!mapped) {
      mapped = await fetchOpeniSingleResult(req, job);
    }
    if (!mapped) {
      continue;
    }
    const dedupeKey = mapped.thumbnailUrl || mapped.imageUrl;
    if (!dedupeKey || seen.has(dedupeKey)) {
      continue;
    }
    seen.add(dedupeKey);
    out.push(mapped);
  }

  return out;
}

function sanitizeImageQuery(value) {
  if (typeof value !== 'string' || !value.trim()) {
    return '';
  }

  return value.replace(/\s+/g, ' ').trim().slice(0, 80);
}

function mapOpeniResult(req, item, query, job) {
  const imageUrl = toAbsoluteUrl(item?.imgLarge || item?.imgThumbLarge);
  const thumbnailUrl = toAbsoluteUrl(
    item?.imgThumbLarge || item?.imgThumb || item?.imgGrid150 || item?.imgLarge,
  );

  if (!imageUrl && !thumbnailUrl) {
    return null;
  }

  const choiceTextShort = job ? truncateText(job.choiceText, 72) : '';
  const titleBase = stripHtml(item?.title) || 'Open-i image result';
  return {
    title: job
        ? `Option ${job.choiceKey}${
          choiceTextShort ? ` — ${choiceTextShort}` : ''
        }`
        : titleBase,
    caption: job
        ? `Open-i — ${stripHtml(item?.image?.caption) || job.query}`
        : stripHtml(item?.image?.caption) || 'No caption was available.',
    imageUrl: buildImageProxyUrl(req, imageUrl || thumbnailUrl),
    thumbnailUrl: buildImageProxyUrl(req, thumbnailUrl || imageUrl),
    sourceUrl: normalizeSourceUrl(
      item?.fulltext_html_url || item?.pmc_url || item?.pubMed_url,
    ),
    sourceLabel: stripHtml(item?.journal_title) || 'Open-i',
    query,
    choiceKey: job?.choiceKey || '',
    choiceTextSnippet: job ? truncateText(job.choiceText, 200) : '',
  };
}

function buildImageProxyUrl(req, targetUrl) {
  if (!targetUrl) {
    return '';
  }

  const url = new URL('/api/openi-image', deploymentBaseUrl(req));
  url.searchParams.set('url', targetUrl);
  return url.toString();
}

function deploymentBaseUrl(req) {
  const forwardedProto = headerValue(req, 'x-forwarded-proto');
  const forwardedHost = headerValue(req, 'x-forwarded-host');
  const host = forwardedHost || headerValue(req, 'host');
  const protocol = forwardedProto || 'https';
  return `${protocol}://${host}`;
}

function headerValue(req, name) {
  const value = req?.headers?.[name];
  if (Array.isArray(value)) {
    return value[0] || '';
  }
  return typeof value === 'string' ? value : '';
}

function toAbsoluteUrl(path) {
  if (typeof path !== 'string' || !path.trim()) {
    return '';
  }

  try {
    return new URL(path, OPENI_BASE_URL).toString();
  } catch (_) {
    return '';
  }
}

function normalizeSourceUrl(url) {
  if (typeof url !== 'string' || !url.trim()) {
    return '';
  }

  if (url.startsWith('http://')) {
    return `https://${url.slice('http://'.length)}`;
  }

  if (url.startsWith('https://')) {
    return url;
  }

  return toAbsoluteUrl(url);
}

function stripHtml(value) {
  if (typeof value !== 'string') {
    return '';
  }

  return value
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseJsonObjectFromText(text) {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }

  const firstBrace = text.indexOf('{');
  const lastBrace = text.lastIndexOf('}');
  if (firstBrace < 0 || lastBrace <= firstBrace) {
    return null;
  }

  return parseJsonSafely(text.slice(firstBrace, lastBrace + 1));
}

function parseJsonSafely(text) {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}
