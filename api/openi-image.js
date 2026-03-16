const ALLOWED_HOSTS = new Set(['openi.nlm.nih.gov']);

module.exports = async (req, res) => {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Only GET is supported.' });
    return;
  }

  const rawUrl = `${req.query?.url || ''}`.trim();
  if (!rawUrl) {
    res.status(400).json({ error: 'url is required.' });
    return;
  }

  let targetUrl;
  try {
    targetUrl = new URL(rawUrl);
  } catch (_) {
    res.status(400).json({ error: 'Invalid url.' });
    return;
  }

  if (!ALLOWED_HOSTS.has(targetUrl.hostname)) {
    res.status(400).json({ error: 'Unsupported image host.' });
    return;
  }

  try {
    const upstream = await fetch(targetUrl, {
      headers: {
        'User-Agent': 'CoreReviewImageProxy/1.0',
      },
    });

    if (!upstream.ok) {
      res.status(upstream.status).json({
        error: `Upstream image request failed with ${upstream.status}.`,
      });
      return;
    }

    const contentType =
      upstream.headers.get('content-type') || 'application/octet-stream';
    const cacheControl =
      upstream.headers.get('cache-control') || 'public, max-age=86400';
    const buffer = Buffer.from(await upstream.arrayBuffer());

    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', cacheControl);
    res.status(200).send(buffer);
  } catch (error) {
    res.status(500).json({
      error:
        error instanceof Error
          ? error.message
          : 'Unable to load upstream image.',
    });
  }
};

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}
