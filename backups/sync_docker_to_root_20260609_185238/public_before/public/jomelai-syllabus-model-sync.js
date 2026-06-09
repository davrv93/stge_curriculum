(function () {
  var MODEL = "llama3.2:1b";
  window.JOMELAI_SYLLABUS_MODEL = MODEL;

  console.log("[JoMelAi] Syllabus model sync activo:", MODEL);

  var originalFetch = window.fetch;

  if (!originalFetch || originalFetch.__jomelaiSyllabusModelSync) {
    return;
  }

  function isSyllabusUrl(input) {
    var url = "";

    if (typeof input === "string") {
      url = input;
    } else if (input && input.url) {
      url = input.url;
    }

    return url.indexOf("/api/assistant/generate-syllabus-stream") !== -1;
  }

  function cloneOptions(init) {
    var out = {};
    init = init || {};

    Object.keys(init).forEach(function (k) {
      out[k] = init[k];
    });

    return out;
  }

  window.fetch = function (input, init) {
    if (!isSyllabusUrl(input)) {
      return originalFetch.apply(this, arguments);
    }

    var opts = cloneOptions(init);

    try {
      var body = opts.body;

      if (typeof body === "string" && body.trim().charAt(0) === "{") {
        var payload = JSON.parse(body);

        var previous = payload.model;
        payload.model = MODEL;

        opts.body = JSON.stringify(payload);

        console.log("[JoMelAi] Syllabus request model sincronizado", {
          previous_model: previous,
          model: MODEL,
          url: typeof input === "string" ? input : input.url
        });

        return originalFetch.call(this, input, opts);
      }
    } catch (e) {
      console.warn("[JoMelAi] No se pudo sincronizar model del request:", e);
    }

    return originalFetch.apply(this, arguments);
  };

  window.fetch.__jomelaiSyllabusModelSync = true;
})();
