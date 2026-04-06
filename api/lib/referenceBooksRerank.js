const {
  resolveModel,
  buildStudyContextMessage,
} = require('./referenceBooksLlm');

function openAiReasoningPayload(model) {
  if (/nano|mini/i.test(model) && !/^o/i.test(model)) {
    return {};
  }
  if (/^gpt-5|^o3|^o4/i.test(model)) {
    return { reasoning: { effort: 'low' } };
  }
  return {};
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

const RERANK_SYSTEM = `You are helping a radiology resident find the best Crack the Core (CTC) and War Machine textbook PAGE excerpts for a board-review question.

You receive a list of candidate pages with short excerpts. Rank them by semantic relevance to the MAIN teaching point of the question (pathophysiology, imaging pattern, key findings)—not keyword overlap alone.

Rules:
- Use study context; if studyModeNoReveal is true, do not assume which multiple-choice option is correct when ranking.
- Return rankedCandidateIds: EVERY candidate id exactly ONCE, ordered BEST (most relevant) to WORST.
- Candidate ids look like cand:0, cand:1, … Copy each exactly once.
- Do not invent ids or omit any id from the list.`;

/**
 * @param {{
 *   apiKey: string,
 *   studyContext: object,
 *   topic: string,
 *   searchPhrases: string[],
 *   candidates: { id: string, bookLabel: string, page: number, fileName: string, snippet: string }[],
 * }} params
 * @returns {Promise<string[]>} candidate ids best-first
 */
async function rerankReferencePagesWithLlm(params) {
  const { apiKey, studyContext, topic, searchPhrases, candidates } = params;
  if (!candidates.length) {
    return [];
  }

  const noReveal = !studyContext.allowAnswerReveal;
  const blocks = candidates.map((c) => {
    const snip = `${c.snippet || ''}`
      .slice(0, 720)
      .replace(/\s+/g, ' ')
      .trim();
    return [
      `id: ${c.id}`,
      `book: ${c.bookLabel}`,
      `page: ${c.page}`,
      `file: ${c.fileName}`,
      `excerpt: ${snip}`,
    ].join('\n');
  });

  const userPayload = [
    `studyModeNoReveal: ${noReveal ? 'true' : 'false'}`,
    '',
    buildStudyContextMessage(studyContext),
    '',
    `Derived topic: ${topic || '(none)'}`,
    `Literature search phrases: ${(searchPhrases || []).join(' | ') || '(none)'}`,
    '',
    'Rank these candidates (copy id strings exactly; include every id once):',
    '',
    ...blocks.map((b) => `---\n${b}`),
  ].join('\n');

  const model = resolveModel();
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      ...openAiReasoningPayload(model),
      max_output_tokens: 1200,
      text: {
        format: {
          type: 'json_schema',
          name: 'reference_book_rerank',
          strict: true,
          schema: {
            type: 'object',
            additionalProperties: false,
            properties: {
              rankedCandidateIds: {
                type: 'array',
                items: { type: 'string' },
              },
            },
            required: ['rankedCandidateIds'],
          },
        },
      },
      input: [
        {
          role: 'system',
          content: [{ type: 'input_text', text: RERANK_SYSTEM }],
        },
        {
          role: 'user',
          content: [{ type: 'input_text', text: userPayload }],
        },
      ],
    }),
  });

  const rawText = await response.text();
  const payload = parseJsonSafely(rawText);
  if (!response.ok) {
    const msg =
      payload?.error?.message ||
      'The OpenAI request for reference page reranking failed.';
    throw new Error(msg);
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error('Empty model response for reference rerank.');
  }

  const obj =
    parseJsonSafely(outputText) || parseJsonObjectFromText(outputText);
  if (!obj || typeof obj !== 'object') {
    throw new Error('Invalid JSON from reference rerank model.');
  }

  const raw = Array.isArray(obj.rankedCandidateIds)
    ? obj.rankedCandidateIds
    : [];
  const ranked = raw
    .filter((x) => typeof x === 'string' && x.trim())
    .map((x) => x.trim());

  const expected = new Set(candidates.map((c) => c.id));
  const seen = new Set();
  const ordered = [];
  for (const id of ranked) {
    if (expected.has(id) && !seen.has(id)) {
      seen.add(id);
      ordered.push(id);
    }
  }
  for (const c of candidates) {
    if (!seen.has(c.id)) {
      ordered.push(c.id);
    }
  }
  return ordered;
}

module.exports = {
  rerankReferencePagesWithLlm,
};
