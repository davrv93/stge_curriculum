(function () {
  if (window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__) return;
  window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__ = true;

  const STREAM_URL = '/api/chat-lateral/ask-stream';
  const ASK_URL = '/api/chat-lateral/ask';

  function parseSseChunk(chunk) {
    const eventLine = chunk.split('\n').find(x => x.startsWith('event:'));
    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));
    if (!dataLine) return null;
    try {
      return {
        event: eventLine ? eventLine.slice(6).trim() : 'message',
        data: JSON.parse(dataLine.slice(5).trim())
      };
    } catch (e) {
      return null;
    }
  }

  async function ask(payload) {
    const body = Object.assign({
      table: 'silabos',
      collection: 'silabos',
      n_results: 2,
      chart: true
    }, payload || {});

    const res = await fetch(ASK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    return await res.json();
  }

  async function askStream(payload, onEvent) {
    const body = Object.assign({
      table: 'silabos',
      collection: 'silabos',
      n_results: 2,
      chart: true
    }, payload || {});

    const res = await fetch(STREAM_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    if (!res.body || !res.body.getReader) return res;

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';

    while (true) {
      const item = await reader.read();
      if (item.done) break;

      buffer += decoder.decode(item.value, { stream: true });
      const chunks = buffer.split('\n\n');
      buffer = chunks.pop() || '';

      for (const chunk of chunks) {
        const parsed = parseSseChunk(chunk);
        if (parsed && typeof onEvent === 'function') {
          onEvent(parsed.event, parsed.data);
        }
      }
    }

    return res;
  }

  window.JoMelAiChatLateralV2 = {
    ask,
    askStream,
    STREAM_URL,
    ASK_URL,
    version: 'asset-fix-v1'
  };

  console.info('[JoMelAi] chat-lateral-v2-client cargado');
})();
