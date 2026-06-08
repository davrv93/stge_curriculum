(function () {
  const STREAM_ENDPOINTS = [
    '/api/chat-lateral/ask-stream',
    '/chat-lateral/ask-stream'
  ];

  async function askStream(question, handlers, options) {
    handlers = handlers || {};
    options = options || {};

    const payload = {
      question: question,
      table: options.table || 'silabos',
      collection: options.collection || 'silabos',
      n_results: options.n_results || 2,
      stream: true,
      prefer_duckdb: true,
      prefer_rag: true,
      allow_ollama: options.allow_ollama !== false,
      chart: true,
      limit: options.limit || 100
    };

    let lastError = null;

    for (const url of STREAM_ENDPOINTS) {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(payload)
        });

        if (!res.ok) {
          throw new Error('HTTP ' + res.status + ' en ' + url);
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder('utf-8');
        let buffer = '';
        let finalData = null;

        while (true) {
          const read = await reader.read();
          if (read.done) break;

          buffer += decoder.decode(read.value, {stream: true});
          const chunks = buffer.split('\n\n');
          buffer = chunks.pop() || '';

          for (const chunk of chunks) {
            const lines = chunk.split('\n');
            let event = 'message';
            let data = '';

            for (const line of lines) {
              if (line.startsWith('event:')) event = line.slice(6).trim();
              if (line.startsWith('data:')) data += line.slice(5).trim();
            }

            if (!data) continue;

            let parsed = {};
            try {
              parsed = JSON.parse(data);
            } catch (e) {
              parsed = {raw: data};
            }

            if (event === 'ready' && handlers.onReady) handlers.onReady(parsed);
            if (event === 'config' && handlers.onConfig) handlers.onConfig(parsed);
            if (event === 'token' && handlers.onToken) handlers.onToken(parsed.text || '', parsed);
            if (event === 'final') {
              finalData = parsed;
              if (handlers.onFinal) handlers.onFinal(parsed);
            }
          }
        }

        return finalData || {ok: true};
      } catch (err) {
        lastError = err;
      }
    }

    throw lastError || new Error('No se pudo conectar al chat lateral v2');
  }

  window.JoMelAiChatLateralV2 = { askStream };
  window.jomelaiChatLateralAskStream = askStream;
})();
