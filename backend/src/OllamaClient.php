<?php

final class OllamaClient
{
    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim((string)Support::config('ollama_base_url'), '/');
    }

    public function health(): array
    {
        try {
            $result = $this->request('GET', '/api/tags', null, 10);
            return [
                'ok' => true,
                'base_url' => $this->baseUrl,
                'models' => $result['models'] ?? [],
            ];
        } catch (Throwable $e) {
            return [
                'ok' => false,
                'base_url' => $this->baseUrl,
                'message' => $e->getMessage(),
                'models' => [],
            ];
        }
    }

    public function models(): array
    {
        return $this->health();
    }

    public function generate(string $prompt, ?string $model = null, array $options = [], ?int $timeoutSeconds = null): array
    {
        $model = $model ?: Support::config('ollama_default_model');

        $payload = [
            'model' => $model,
            'prompt' => $prompt,
            'stream' => false,
            'keep_alive' => Support::config('ollama_keep_alive') ?: '10m',
            'options' => array_merge([
                'temperature' => 0.20,
                'top_p' => 0.85,
                'num_ctx' => (int)Support::config('ollama_plan_ctx'),
                'num_predict' => (int)Support::config('ollama_plan_predict'),
                'repeat_penalty' => 1.08,
            ], $options),
        ];

        return $this->request('POST', '/api/generate', $payload, $timeoutSeconds);
    }

    public function generateFast(string $prompt, ?string $model = null, array $options = [], ?int $timeoutSeconds = null): array
    {
        $options = array_merge([
            'temperature' => 0.15,
            'top_p' => 0.82,
            'num_ctx' => (int)Support::config('ollama_plan_ctx'),
            'num_predict' => (int)Support::config('ollama_plan_predict'),
            'repeat_penalty' => 1.08,
        ], $options);

        return $this->generate(
            $prompt,
            $model,
            $options,
            $timeoutSeconds ?: (int)Support::config('ollama_plan_timeout')
        );
    }

    private function request(string $method, string $path, ?array $payload = null, ?int $timeoutSeconds = null): array
    {
        $url = $this->baseUrl . $path;

        $timeout = max(1, $timeoutSeconds ?: (int)Support::config('ollama_http_timeout'));

        $headers = [
            'Content-Type: application/json',
            'Connection: close',
        ];

        $opts = [
            'http' => [
                'method' => $method,
                'header' => implode("\r\n", $headers),
                'timeout' => $timeout,
                'ignore_errors' => true,
            ],
        ];

        if ($payload !== null) {
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if ($encoded === false) {
                throw new RuntimeException('No se pudo serializar el payload para Ollama.');
            }
            $opts['http']['content'] = $encoded;
        }

        $context = stream_context_create($opts);
        $started = microtime(true);
        $raw = @file_get_contents($url, false, $context);
        $elapsed = round(microtime(true) - $started, 3);

        if ($raw === false) {
            $last = error_get_last();
            $detail = is_array($last) && isset($last['message']) ? $last['message'] : 'sin detalle';

            throw new RuntimeException(
                'No se pudo completar la llamada a Ollama en ' . $this->baseUrl .
                '. Posible timeout o corte de conexión. Timeout=' . $timeout .
                's, elapsed=' . $elapsed . 's. Detalle: ' . $detail
            );
        }

        $statusLine = $http_response_header[0] ?? 'HTTP/1.1 200 OK';
        if (!preg_match('/\s(\d{3})\s/', $statusLine, $m)) {
            $status = 200;
        } else {
            $status = (int)$m[1];
        }

        $json = json_decode($raw, true);

        if ($status >= 400) {
            throw new RuntimeException(
                'Ollama respondió HTTP ' . $status .
                ' en ' . $elapsed . 's. Respuesta: ' . Support::strLimit($raw, 800)
            );
        }

        if (!is_array($json)) {
            throw new RuntimeException(
                'Respuesta inválida de Ollama en ' . $elapsed .
                's: ' . Support::strLimit($raw, 800)
            );
        }

        return $json;
    }
}
