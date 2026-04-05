const fs = require('fs');
const path = require('path');
const { deriveSearchPlanFromLlm } = require('./lib/referenceBooksLlm');

const STOP = new Set([
  'the',
  'and',
  'for',
  'with',
  'that',
  'this',
  'from',
  'are',
  'was',
  'has',
  'have',
  'been',
  'not',
  'but',
  'may',
  'can',
  'its',
  'one',
  'two',
  'also',
  'more',
  'such',
  'than',
  'into',
  'using',
  'used',
  'when',
  'which',
  'while',
  'will',
  'other',
]);

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

  const body = parseBody(req.body);
  const queryParam = `${body.query || ''}`.trim();
  const studyContext = body.studyContext && typeof body.studyContext === 'object'
    ? body.studyContext
    : null;

  const hasStudy =
    studyContext &&
    (`${studyContext.prompt || ''}`.trim() !== '' ||
      (studyContext.choices && Object.keys(studyContext.choices).length > 0));

  if (!queryParam && !hasStudy) {
    res
      .status(400)
      .json({ error: 'Provide studyContext (prompt/choices) or query.' });
    return;
  }

  const indexPath = path.join(__dirname, 'reference_books_index.json');
  let raw;
  try {
    raw = fs.readFileSync(indexPath, 'utf8');
  } catch (_) {
    res.status(200).json({
      matches: [],
      searchMeta: null,
      message:
        'No reference book index found. Run: python tool/build_reference_book_index.py <path-to-pdfs>',
    });
    return;
  }

  let data;
  try {
    data = JSON.parse(raw);
  } catch (_) {
    res.status(500).json({ error: 'reference_books_index.json is invalid JSON.' });
    return;
  }

  const pages = Array.isArray(data.pages) ? data.pages : [];
  const pdfUrlsByFileName =
    data.pdfUrlsByFileName && typeof data.pdfUrlsByFileName === 'object'
      ? data.pdfUrlsByFileName
      : null;

  if (pages.length === 0) {
    res.status(200).json({
      matches: [],
      searchMeta: null,
      message: 'Reference book index is empty. Build it with tool/build_reference_book_index.py',
    });
    return;
  }

  const apiKey = process.env.OPENAI_API_KEY || '';
  let searchMeta = {
    topic: '',
    searchPhrases: [],
    usedLlm: false,
    llmError: null,
    fallbackNote: null,
  };

  if (hasStudy && apiKey) {
    try {
      const plan = await deriveSearchPlanFromLlm({ apiKey, studyContext });
      searchMeta.topic = plan.topic;
      searchMeta.searchPhrases = plan.searchPhrases;
      searchMeta.usedLlm = true;
    } catch (err) {
      searchMeta.llmError =
        err instanceof Error ? err.message : 'Reference search model failed.';
      searchMeta.fallbackNote =
        'Model call failed; using raw question text for keyword search.';
    }
  } else if (hasStudy && !apiKey) {
    searchMeta.fallbackNote =
      'OPENAI_API_KEY not set; using raw question text for keyword search.';
  }

  const combinedText = buildCombinedSearchText({
    queryParam,
    studyContext,
    searchMeta,
    hasStudy,
  });

  const phrasesForScore = pickPhrasesForScoring(searchMeta);
  const tokens = tokenize(combinedText);
  if (tokens.length === 0 && phrasesForScore.length === 0) {
    res.status(200).json({
      matches: [],
      searchMeta,
      message: 'No searchable terms produced from the question.',
    });
    return;
  }

  const scored = pages
    .map((p) => ({
      page: p,
      score: scorePage(p, tokens, phrasesForScore),
    }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 12);

  const matches = scored.map(({ page, score }) => {
    const fileName = page.fileName || '';
    const pdfUrl =
      pdfUrlsByFileName &&
      Object.prototype.hasOwnProperty.call(pdfUrlsByFileName, fileName)
        ? `${pdfUrlsByFileName[fileName]}`.trim()
        : '';
    return {
      bookLabel: page.bookLabel || '',
      fileName,
      page: page.page || 0,
      excerpt: excerpt(
        page.text || '',
        tokens,
        phrasesForScore,
        420,
      ),
      fullText: `${page.text || ''}`.trim(),
      pdfUrl,
      score,
    };
  });

  res.status(200).json({
    matches,
    searchMeta: {
      topic: searchMeta.topic,
      searchPhrases: searchMeta.searchPhrases,
      usedLlm: searchMeta.usedLlm,
      llmError: searchMeta.llmError,
      fallbackNote: searchMeta.fallbackNote,
      combinedQueryPreview: combinedText.slice(0, 800),
    },
  });
};

function buildCombinedSearchText({
  queryParam,
  studyContext,
  searchMeta,
  hasStudy,
}) {
  if (searchMeta.usedLlm && (searchMeta.topic || searchMeta.searchPhrases.length)) {
    return [searchMeta.topic, ...searchMeta.searchPhrases].join(' ').trim();
  }
  if (queryParam) {
    return queryParam;
  }
  if (hasStudy) {
    return fallbackQueryFromStudy(studyContext);
  }
  return '';
}

function fallbackQueryFromStudy(studyContext) {
  const parts = [];
  if (studyContext.prompt) {
    parts.push(studyContext.prompt);
  }
  if (studyContext.choices && typeof studyContext.choices === 'object') {
    for (const v of Object.values(studyContext.choices)) {
      if (typeof v === 'string' && v.trim()) {
        parts.push(v);
      }
    }
  }
  if (studyContext.chapterTitle) {
    parts.push(studyContext.chapterTitle);
  }
  if (studyContext.topicTitle) {
    parts.push(studyContext.topicTitle);
  }
  return parts.join('\n').slice(0, 12000);
}

function pickPhrasesForScoring(searchMeta) {
  if (!searchMeta.usedLlm) {
    return [];
  }
  const out = [];
  if (searchMeta.topic && searchMeta.topic.length > 3) {
    out.push(searchMeta.topic.replace(/\s+/g, ' ').trim());
  }
  for (const p of searchMeta.searchPhrases || []) {
    const t = `${p}`.replace(/\s+/g, ' ').trim();
    if (t.length > 2) {
      out.push(t);
    }
  }
  return dedupePhrases(out);
}

function dedupePhrases(phrases) {
  const seen = new Set();
  const out = [];
  for (const p of phrases) {
    const key = p.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      out.push(p);
    }
  }
  return out.slice(0, 16);
}

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

function tokenize(text) {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/g)
    .filter((t) => t.length > 2 && !STOP.has(t));
}

function scorePage(page, tokens, phrases) {
  const hay = `${page.text || ''} ${page.bookLabel || ''}`.toLowerCase();
  let s = 0;
  const hitTokens = new Set();
  for (const t of tokens) {
    if (hay.includes(t)) {
      if (!hitTokens.has(t)) {
        hitTokens.add(t);
        s += 1;
      }
    }
  }
  const hitPhrases = new Set();
  for (const p of phrases) {
    const pl = p.toLowerCase();
    if (pl.length >= 4 && hay.includes(pl) && !hitPhrases.has(pl)) {
      hitPhrases.add(pl);
      s += 5;
    }
  }
  return s;
}

function excerpt(text, tokens, phrases, maxLen) {
  if (!text.trim()) {
    return '';
  }
  const lower = text.toLowerCase();
  let best = -1;
  let bestPhraseLen = 0;

  for (const p of phrases) {
    const pl = p.toLowerCase();
    if (pl.length < 3) {
      continue;
    }
    const i = lower.indexOf(pl);
    if (i >= 0 && (best < 0 || i < best || (i === best && pl.length > bestPhraseLen))) {
      best = i;
      bestPhraseLen = pl.length;
    }
  }

  if (best < 0) {
    for (const t of tokens) {
      const i = lower.indexOf(t);
      if (i >= 0 && (best < 0 || i < best)) {
        best = i;
      }
    }
  }

  if (best < 0) {
    return text.slice(0, maxLen) + (text.length > maxLen ? '…' : '');
  }

  let start = best > 56 ? best - 56 : 0;
  const paraStart = text.lastIndexOf('\n\n', start);
  if (paraStart >= 0 && paraStart + 2 < start) {
    start = paraStart + 2;
  } else {
    const lineStart = text.lastIndexOf('\n', start);
    if (lineStart >= 0 && start - lineStart < 88) {
      start = lineStart + 1;
    }
  }

  let slice = text.slice(start, start + maxLen);
  const lastNl = slice.lastIndexOf('\n\n');
  if (lastNl > maxLen * 0.65 && lastNl > 0) {
    slice = slice.slice(0, lastNl);
  }
  if (start > 0) {
    slice = '…' + slice.trimStart();
  }
  if (text.length > start + slice.length) {
    slice = slice.trimEnd() + '…';
  }
  return slice.trim() || text.slice(0, maxLen);
}
