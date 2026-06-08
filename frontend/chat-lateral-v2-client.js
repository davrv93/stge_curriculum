(function () {
  if (window.__JOMELAI_CHAT_LATERAL_CLIENT__) return;
  window.__JOMELAI_CHAT_LATERAL_CLIENT__ = true;

  const STREAM_URL = '/api/chat-lateral/ask-stream';
  const ASK_URL = '/api/chat-lateral/ask';

  function normalizePayload(input) {
    input = input || {};
    let question =
      input.question ||
      input.message ||
      input.prompt ||
      input.text ||
      '';

    if (!question && Array.isArray(input.messages) && input.messages.length) {
      const last = input.messages[input.messages.length - 1];
      question = last.content || last.text || '';
    }

    return {
      question: String(question || '').trim(),
      table: input.table || 'silabos',
      collection: input.collection || 'silabos',
      n_results: Number(input.n_results || 2),
      stream: true,
      prefer_duckdb: true,
      prefer_rag: true,
      allow_ollama: input.allow_ollama !== false,
      chart: true,
      limit: Number(input.limit || 100)
    };
  }

  async function askStream(question, handlers, options) {
    handlers = handlers || {};
    options = options || {};

    const payload = normalizePayload({
      question,
      table: options.table,
      collection: options.collection,
      n_results: options.n_results,
      limit: options.limit,
      allow_ollama: options.allow_ollama
    });

    const res = await fetch(STREAM_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) throw new Error('HTTP ' + res.status + ' en ' + STREAM_URL);

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';
    let finalData = null;

    while (true) {
      const read = await reader.read();
      if (read.done) break;

      buffer += decoder.decode(read.value, { stream: true });
      const chunks = buffer.split('\n\n');
      buffer = chunks.pop() || '';

      chunks.forEach(chunk => {
        const lines = chunk.split('\n');
        let event = 'message';
        let dataLine = '';

        lines.forEach(line => {
          if (line.startsWith('event:')) event = line.slice(6).trim();
          if (line.startsWith('data:')) dataLine += line.slice(5).trim();
        });

        if (!dataLine) return;

        let data = {};
        try { data = JSON.parse(dataLine); } catch (e) { data = { raw: dataLine }; }

        if (event === 'ready' && handlers.onReady) handlers.onReady(data);
        if (event === 'config' && handlers.onConfig) handlers.onConfig(data);
        if (event === 'token' && handlers.onToken) handlers.onToken(data.text || '', data);
        if (event === 'final') {
          finalData = data;
          if (handlers.onFinal) handlers.onFinal(data);
          if (window.JoMelAiChatPanelRenderer && window.JoMelAiChatPanelRenderer.renderPayload) {
            window.JoMelAiChatPanelRenderer.renderPayload(data);
          }
        }
      });
    }

    return finalData || { ok: true };
  }

  async function ask(question, options) {
    options = options || {};
    const payload = normalizePayload({ question, ...options });

    const res = await fetch(ASK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) throw new Error('HTTP ' + res.status + ' en ' + ASK_URL);
    return await res.json();
  }

  window.JoMelAiChatLateralV2 = { askStream, ask, streamUrl: STREAM_URL, askUrl: ASK_URL };
  window.jomelaiChatLateralAskStream = askStream;
  window.jomelaiChatLateralAsk = ask;

  console.info('[JoMelAi] chat-lateral-v2-client cargado');
})();
