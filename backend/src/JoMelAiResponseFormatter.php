<?php
/**
 * Normaliza respuestas internas de JoMelAi para que el frontend siempre reciba
 * un contrato estable. Esto evita que /api/ask falle cuando un motor devuelve
 * tablas, gráficos, SQL, RAG o texto libre con estructuras distintas.
 */
final class JoMelAiResponseFormatter
{
    public function format(array $intentResult, array $engineResult, bool $includeDebug = false, bool $isAdmin = false): array
    {
        $intent = (string)($intentResult['intent'] ?? 'unknown');
        $visible = (string)($intentResult['visible_intent'] ?? $this->visibleIntent($intent));
        $ok = (bool)($engineResult['ok'] ?? true);

        $answer = $this->pickAnswer($engineResult, $intent);
        $table = $this->pickTable($engineResult);
        $chart = $this->pickChart($engineResult);

        $response = [
            'ok' => $ok,
            'intent' => $intent,
            'visible_intent' => $visible,
            'mode' => (string)($engineResult['_engine'] ?? $intent),
            'message' => $ok ? '' : (string)($engineResult['message'] ?? 'No se pudo procesar la solicitud.'),
            'summary' => $answer,
            'answer' => $answer,
            'chart_url' => $engineResult['chart_url'] ?? ($chart['chart_url'] ?? null),
            'data_url' => $engineResult['data_url'] ?? ($chart['data_url'] ?? null),
            'chart' => $chart,
            'table' => $table,
            'sql' => $engineResult['_sql'] ?? $engineResult['sql'] ?? null,
            'evidence' => $engineResult['evidence'] ?? $engineResult['sources'] ?? [],
            'actions' => $engineResult['actions'] ?? [],
            'suggestions' => $engineResult['suggestions'] ?? $this->defaultSuggestions($intent),
        ];

        if (($isAdmin || $includeDebug) && $includeDebug) {
            $response['debug'] = [
                'intent_result' => $intentResult,
                'engine' => $engineResult['_engine'] ?? null,
                'model' => $engineResult['_model'] ?? null,
                'duration_ms' => $engineResult['_duration_ms'] ?? null,
                'raw' => $engineResult,
            ];
        }

        return $response;
    }

    private function pickAnswer(array $r, string $intent): string
    {
        foreach (['answer', 'response', 'summary', 'message', 'explanation', 'markdown'] as $key) {
            if (isset($r[$key]) && trim((string)$r[$key]) !== '') {
                return trim((string)$r[$key]);
            }
        }
        if (isset($r['query']['rows']) && is_array($r['query']['rows'])) {
            return 'Consulta ejecutada correctamente. Revisa la tabla de resultados.';
        }
        if (isset($r['rows']) && is_array($r['rows'])) {
            return 'Consulta ejecutada correctamente. Revisa la tabla de resultados.';
        }
        if ($intent === 'chart') {
            return 'Gráfico generado correctamente desde la base curricular local.';
        }
        return 'Solicitud procesada por JoMelAi.';
    }

    private function pickTable(array $r): ?array
    {
        if (isset($r['table']) && is_array($r['table'])) {
            return $r['table'];
        }
        if (isset($r['query']) && is_array($r['query'])) {
            return [
                'columns' => $r['query']['columns'] ?? [],
                'rows' => $r['query']['rows'] ?? [],
            ];
        }
        if (isset($r['rows']) && is_array($r['rows'])) {
            return [
                'columns' => $r['columns'] ?? [],
                'rows' => $r['rows'],
            ];
        }
        return null;
    }

    private function pickChart(array $r): ?array
    {
        if (isset($r['chart']) && is_array($r['chart'])) {
            return $r['chart'];
        }
        if (isset($r['chart_url']) || isset($r['image_base64'])) {
            return [
                'chart_url' => $r['chart_url'] ?? null,
                'data_url' => $r['data_url'] ?? null,
                'image_base64' => $r['image_base64'] ?? null,
                'chart_type' => $r['chart_type'] ?? null,
            ];
        }
        return null;
    }

    private function visibleIntent(string $intent): string
    {
        return match ($intent) {
            'chart' => 'Gráfico curricular',
            'statistics' => 'Consulta de datos',
            'semantic_search' => 'Búsqueda semántica',
            'syllabus_generation' => 'Generación de sílabo',
            'study_plan' => 'Plan de estudios',
            'curriculum_grid' => 'Malla curricular',
            'report' => 'Reporte curricular',
            default => 'Asistente curricular',
        };
    }

    private function defaultSuggestions(string $intent): array
    {
        return match ($intent) {
            'study_plan', 'curriculum_grid' => ['Definir perfil de egreso', 'Validar créditos y horas', 'Mapear competencias por ciclo'],
            'syllabus_generation' => ['Agregar sumilla', 'Alinear resultados de aprendizaje', 'Completar evaluación por unidades'],
            'chart', 'statistics' => ['Filtrar por programa', 'Agrupar por ciclo', 'Exportar tabla'],
            default => ['Pedir una versión en formato plantilla', 'Contextualizar por institución', 'Solicitar análisis SUNEDU'],
        };
    }
}
