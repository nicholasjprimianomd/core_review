const fs = require('fs');
const path = require('path');

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
  const query = `${body.query || ''}`.trim();
  if (!query) {
    res.status(400).json({ error: 'query is required.' });
    return;
  }

  const indexPath = path.join(__dirname, 'reference_books_index.json');
  let raw;
  try {
    raw = fs.readFileSync(indexPath, 'utf8');
  } catch (_) {
    res.status(200).json({
      matches: [],
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
  if (pages.length === 0) {
    res.status(200).json({
      matches: [],
      message: 'Reference book index is empty. Build it with tool/build_reference_book_index.py',
    });
    return;
  }

  const tokens = tokenize(query);
  if (tokens.length === 0) {
    res.status(200).json({ matches: [], message: 'No searchable terms in query.' });
    return;
  }

  const scored = pages
    .map((p) => ({
      page: p,
      score: scorePage(p, tokens),
    }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 12);

  const matches = scored.map(({ page, score }) => ({
    bookLabel: page.bookLabel || '',
    fileName: page.fileName || '',
    page: page.page || 0,
    excerpt: excerpt(page.text || '', tokens),
    score,
  }));

  res.status(200).json({ matches });
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

function scorePage(page, tokens) {
  const hay = `${page.text || ''} ${page.bookLabel || ''}`.toLowerCase();
  let s = 0;
  for (const t of tokens) {
    if (hay.includes(t)) {
      s += 1;
    }
  }
  return s;
}

function excerpt(text, tokens, maxLen = 320) {
  const lower = text.toLowerCase();
  let best = 0;
  for (const t of tokens) {
    const i = lower.indexOf(t);
    if (i >= 0 && (best === 0 || i < best)) {
      best = i;
    }
  }
  const start = Math.max(0, best > 40 ? best - 40 : 0);
  let slice = text.slice(start, start + maxLen);
  if (start > 0) {
    slice = '…' + slice;
  }
  if (text.length > start + maxLen) {
    slice = slice + '…';
  }
  return slice.trim() || text.slice(0, maxLen);
}
