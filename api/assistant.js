const DEFAULT_MODEL = process.env.OPENAI_MODEL || 'gpt-5-mini';
const OPENI_BASE_URL = 'https://openi.nlm.nih.gov';

const SYSTEM_PROMPT = `
You are the Core Review study assistant for radiology board-review content.

Follow these rules:
- Use only the current question context and the user's request.
- Do not search, cite, or refer to other textbook questions, chapters, or sections.
- Give concise but helpful educational explanations that focus on imaging findings, pathology patterns, and differential clues.
- If answer reveal is not allowed, do not reveal the correct option, do not rank the choices, and do not state which answer is right. Stay in hint mode and focus on concepts, image patterns, and reasoning strategies.
- If answer reveal is allowed, you may explain why the correct answer is right and why distractors are less likely.
- Always provide focused search terms for open-access medical web image search.
- Search terms should be specific pathology or imaging-pattern phrases, ideally including modality when useful.
- Do not claim to have inspected any image unless image content was actually provided.
- If the supplied context does not support a claim, say so plainly.
- This is for study support, not patient care.

Return a JSON object with exactly these keys:
- "answer": string
- "searchTerms": string[]

The "searchTerms" values should contain 2 to 4 short, high-yield pathology or imaging phrases, each under 8 words.
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

    if (includeAnswer) {
      const prompt = buildUserPrompt({ userPrompt, studyContext });
      const openAiResponse = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: DEFAULT_MODEL,
          reasoning: { effort: 'low' },
          max_output_tokens: 900,
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
                },
                required: ['answer', 'searchTerms'],
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

      const assistantPayload =
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

    const webImages = includeWebImages
      ? await fetchWebImages({
          req,
          searchTerms,
          studyContext,
        })
      : [];

    res.status(200).json({
      answer,
      searchTerms,
      webImages,
      model: includeAnswer ? DEFAULT_MODEL : '',
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
  return [
    'Use only the following current question context and user request.',
    'Do not refer to other textbook content.',
    'Respond in JSON.',
    '',
    'User request:',
    userPrompt,
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

async function fetchWebImages({ req, searchTerms, studyContext }) {
  const queries = buildImageQueries({ searchTerms, studyContext });
  if (queries.length === 0) {
    return [];
  }

  const results = await Promise.all(
    queries.map(async (query) => {
      try {
        const url = new URL('/search', OPENI_BASE_URL);
        url.searchParams.set('query', query);
        url.searchParams.set('it', 'xg');
        url.searchParams.set('m', '1');
        url.searchParams.set('n', '3');

        const response = await fetch(url);
        if (!response.ok) {
          return [];
        }

        const payload = await response.json();
        const items = Array.isArray(payload?.list) ? payload.list : [];
        return items
          .map((item) => mapOpeniResult(req, item, query))
          .filter(Boolean);
      } catch (_) {
        return [];
      }
    }),
  );

  const deduped = [];
  const seen = new Set();
  for (const group of results) {
    for (const item of group) {
      if (!item || !item.imageUrl || seen.has(item.imageUrl)) {
        continue;
      }
      seen.add(item.imageUrl);
      deduped.push(item);
      if (deduped.length >= 6) {
        return deduped;
      }
    }
  }

  return deduped;
}

function buildImageQueries({ searchTerms, studyContext }) {
  const queries = [...new Set(searchTerms.map(sanitizeImageQuery).filter(Boolean))];
  if (queries.length > 0) {
    return queries.slice(0, 4);
  }

  const fallbackQueries = [
    studyContext?.correctChoiceText,
  ]
    .map(sanitizeImageQuery)
    .filter(Boolean);

  return [...new Set(fallbackQueries)].slice(0, 2);
}

function sanitizeImageQuery(value) {
  if (typeof value !== 'string' || !value.trim()) {
    return '';
  }

  return value.replace(/\s+/g, ' ').trim().slice(0, 80);
}

function mapOpeniResult(req, item, query) {
  const imageUrl = toAbsoluteUrl(item?.imgLarge || item?.imgThumbLarge);
  const thumbnailUrl = toAbsoluteUrl(
    item?.imgThumbLarge || item?.imgThumb || item?.imgGrid150 || item?.imgLarge,
  );

  if (!imageUrl && !thumbnailUrl) {
    return null;
  }

  return {
    title: stripHtml(item?.title) || 'Open-i image result',
    caption: stripHtml(item?.image?.caption) || 'No caption was available.',
    imageUrl: buildImageProxyUrl(req, imageUrl || thumbnailUrl),
    thumbnailUrl: buildImageProxyUrl(req, thumbnailUrl || imageUrl),
    sourceUrl: normalizeSourceUrl(
      item?.fulltext_html_url || item?.pmc_url || item?.pubMed_url,
    ),
    sourceLabel: stripHtml(item?.journal_title) || 'Open-i',
    query,
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
