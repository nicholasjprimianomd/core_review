function resolveModel() {
  return process.env.OPENAI_MODEL || 'gpt-5.4-nano';
}

function openAiReasoningPayload(model) {
  if (/nano|mini/i.test(model) && !/^o/i.test(model)) {
    return {};
  }
  if (/^gpt-5|^o3|^o4/i.test(model)) {
    return { reasoning: { effort: 'low' } };
  }
  return {};
}

const REFERENCE_SEARCH_SYSTEM = `You are helping a radiology resident search textbook passages in books like Crack the Core and War Machine.
Return JSON only (schema enforced by the API). Your job:
- Infer the main 1-2 educational topics (pathology, anatomy, imaging pattern, or physics concept) from the question.
- Propose searchPhrases: 5 to 10 short strings (2 to 8 words each) that are likely to appear literally in dense review text—disease names, eponyms, modality + anatomy, classic sign names, abbreviations (CT, MRI, US), pattern names.
- If studyModeNoReveal is true, do not say which option is correct; still derive neutral keywords from the stem and every answer choice.
- Do not give patient care instructions.`;

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

function buildStudyContextMessage(studyContext) {
  const lines = [];
  if (studyContext.questionNumber) {
    lines.push(`Question number: ${studyContext.questionNumber}`);
  }
  if (studyContext.chapterTitle) {
    lines.push(`Chapter: ${studyContext.chapterTitle}`);
  }
  if (studyContext.topicTitle) {
    lines.push(`Topic: ${studyContext.topicTitle}`);
  }
  if (studyContext.prompt) {
    lines.push(`Prompt:\n${studyContext.prompt}`);
  }
  if (studyContext.choices && typeof studyContext.choices === 'object') {
    lines.push('Answer choices:');
    const keys = Object.keys(studyContext.choices).sort();
    for (const k of keys) {
      const v = studyContext.choices[k];
      lines.push(`  ${k}. ${v}`);
    }
  }
  if (studyContext.allowAnswerReveal && studyContext.correctChoiceText) {
    lines.push(
      `Correct answer (for sharper keyword focus only): ${
        studyContext.correctChoiceText
      }`,
    );
  }
  return lines.join('\n');
}

/**
 * @param {{ apiKey: string, studyContext: object }}
 * @returns {Promise<{ topic: string, searchPhrases: string[] }>}
 */
async function deriveSearchPlanFromLlm({ apiKey, studyContext }) {
  const userPayload = [
    'studyModeNoReveal:',
    studyContext.allowAnswerReveal ? 'false' : 'true',
    '',
    buildStudyContextMessage(studyContext),
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
      max_output_tokens: 400,
      text: {
        format: {
          type: 'json_schema',
          name: 'reference_book_search_plan',
          strict: true,
          schema: {
            type: 'object',
            additionalProperties: false,
            properties: {
              topic: { type: 'string' },
              searchPhrases: {
                type: 'array',
                items: { type: 'string' },
              },
            },
            required: ['topic', 'searchPhrases'],
          },
        },
      },
      input: [
        {
          role: 'system',
          content: [{ type: 'input_text', text: REFERENCE_SEARCH_SYSTEM }],
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
      payload?.error?.message || 'The OpenAI request for reference search failed.';
    throw new Error(msg);
  }

  const outputText = extractOutputText(payload);
  if (!outputText) {
    throw new Error('Empty model response for reference search.');
  }

  const obj = parseJsonSafely(outputText) || parseJsonObjectFromText(outputText);
  if (!obj || typeof obj !== 'object') {
    throw new Error('Invalid JSON from reference search model.');
  }

  const topic = `${obj.topic || ''}`.trim();
  const phrasesRaw = Array.isArray(obj.searchPhrases) ? obj.searchPhrases : [];
  const searchPhrases = phrasesRaw
    .filter((t) => typeof t === 'string')
    .map((t) => t.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .slice(0, 12);

  return { topic, searchPhrases };
}

module.exports = {
  deriveSearchPlanFromLlm,
  resolveModel,
};
