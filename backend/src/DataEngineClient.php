<?php
final class DataEngineClient
{
    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = Support::config('data_engine_base_url');
    }

    public function get(string $path, array $query = []): array
    {
        $url = $this->baseUrl . $path;
        if ($query) {
            $url .= '?' . http_build_query($query);
        }
        return $this->request('GET', $url, null);
    }

    public function post(string $path, array $payload = []): array
    {
        return $this->request('POST', $this->baseUrl . $path, $payload);
    }

    private function request(string $method, string $url, ?array $payload): array
    {
        $headers = ['Accept: application/json'];
        $content = '';
        if ($payload !== null) {
            $content = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $headers[] = 'Content-Type: application/json';
        }
        $context = stream_context_create([
            'http' => [
                'method' => $method,
                'header' => implode("\r\n", $headers),
                'content' => $content,
                'timeout' => 900,
                'ignore_errors' => true,
            ],
        ]);
        $raw = @file_get_contents($url, false, $context);
        $status = 0;
        if (isset($http_response_header) && is_array($http_response_header)) {
            foreach ($http_response_header as $line) {
                if (preg_match('/^HTTP\/\S+\s+(\d+)/', $line, $m)) {
                    $status = (int)$m[1];
                    break;
                }
            }
        }
        $json = json_decode((string)$raw, true);
        if (!is_array($json)) {
            $json = ['ok' => false, 'message' => 'Respuesta inválida desde data-engine.', 'raw' => Support::strLimit((string)$raw, 500)];
        }
        if ($status >= 400) {
            $detail = $json['detail'] ?? $json['message'] ?? 'Error en data-engine.';
            return ['ok' => false, 'message' => is_string($detail) ? $detail : json_encode($detail, JSON_UNESCAPED_UNICODE), 'status' => $status, 'data' => $json];
        }
        if (!isset($json['ok'])) {
            $json['ok'] = true;
        }
        return $json;
    }
}
