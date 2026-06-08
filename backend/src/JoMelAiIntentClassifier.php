<?php
/**
 * JoMelAiIntentClassifier
 * Classifies natural language questions into structured intent decisions.
 * No technical terms are exposed to the user layer.
 */
final class JoMelAiIntentClassifier
{
    private const INTENT_MAP = [
        'chart' => [
            'visible' => 'Generar gráfico',
            'engine'  => 'data_analysis',
            'requires_chart' => true,
            'requires_evidence' => false,
        ],
        'statistics' => [
            'visible' => 'Consultar datos académicos',
            'engine'  => 'data_analysis',
            'requires_chart' => false,
            'requires_evidence' => false,
        ],
        'semantic_search' => [
            'visible' => 'Búsqueda en sílabos',
            'engine'  => 'knowledge_index',
            'requires_chart' => false,
            'requires_evidence' => true,
        ],
        'course_lookup' => [
            'visible' => 'Búsqueda de curso',
            'engine'  => 'hybrid',
            'requires_chart' => false,
            'requires_evidence' => true,
        ],
        'comparison' => [
            'visible' => 'Comparar cursos',
            'engine'  => 'hybrid',
            'requires_chart' => false,
            'requires_evidence' => true,
        ],
        'syllabus_generation' => [
            'visible' => 'Crear propuesta de sílabo',
            'engine'  => 'assistant',
            'requires_chart' => false,
            'requires_evidence' => true,
        ],
        'study_plan' => [
            'visible' => 'Diseñar plan de estudios',
            'engine'  => 'curriculum',
            'requires_chart' => false,
            'requires_evidence' => false,
        ],
        'curriculum_grid' => [
            'visible' => 'Revisar malla curricular',
            'engine'  => 'curriculum',
            'requires_chart' => false,
            'requires_evidence' => false,
        ],
        'report' => [
            'visible' => 'Generar informe',
            'engine'  => 'hybrid',
            'requires_chart' => true,
            'requires_evidence' => true,
        ],
        'dataset_quality' => [
            'visible' => 'Revisar calidad del dataset',
            'engine'  => 'data_analysis',
            'requires_chart' => false,
            'requires_evidence' => false,
        ],
        'unknown' => [
            'visible' => 'Orientación',
            'engine'  => 'assistant',
            'requires_chart' => false,
            'requires_evidence' => false,
        ],
    ];

    private const RULES = [
        // Higher priority first
        'syllabus_generation' => [
            'generar silabo', 'generar silabos', 'crear silabo', 'crear silabos',
            'propuesta de silabo', 'nuevo silabo', 'disenar silabo', 'disenar curso',
            'nuevo curso', 'elaborar silabo', 'redactar silabo',
        ],
        'comparison' => [
            'compara', 'comparar', 'diferencias entre', 'similitudes entre',
            'contrasta', 'contraste entre', 'versus', ' vs ', 'es mejor que',
            'frente a', 'en relacion con',
        ],
        'study_plan' => [
            'plan de estudios', 'itinerario formativo', 'estructura curricular completa',
            'secuencia de cursos', 'organiza los cursos', 'arma el plan',
        ],
        'curriculum_grid' => [
            'malla curricular', 'ciclo', 'creditos', 'prerrequisitos',
            'estructura curricular', 'distribucion de ciclos', 'malla de',
        ],
        'report' => [
            'reporte', 'informe', 'resumen ejecutivo', 'diagnostico curricular',
            'analisis curricular', 'genera un informe', 'elabora un reporte',
            'exporta un reporte', 'sintesis de',
        ],
        'dataset_quality' => [
            'incompleto', 'vacios', 'nulos', 'duplicados', 'calidad de datos',
            'errores del dataset', 'datos faltantes', 'columnas vacias',
            'revisar datos', 'inconsistencias',
        ],
        'chart' => [
            'grafico', 'grafica', 'barras', 'linea', 'pastel', 'pie',
            'visualiza', 'diagrama', 'ranking visual', 'distribucion visual',
            'chart', 'muestra visualmente', 'ilustra', 'representa graficamente',
        ],
        'statistics' => [
            'cuantos', 'cuantas', 'cantidad de', 'total de', 'promedio',
            'listar', 'lista de', 'por facultad', 'por programa', 'por periodo',
            'conteo', 'contar', 'suma de', 'ranking de', 'top ', 'porcentaje de',
            'distribucion de', 'cuanto hay', 'cuantos hay',
        ],
        'semantic_search' => [
            'competencias', 'competencia de', 'sumilla', 'contenidos de',
            'bibliografia de', 'resultados de aprendizaje', 'metodologia de',
            'metodologia del', 'evaluacion del', 'evaluacion de', 'enfoque de',
            'integracion fe', 'valores en', 'etica en', 'etica del',
            'que dice', 'que menciona', 'como aborda', 'que incluye',
        ],
        'course_lookup' => [
            'buscar curso', 'encontrar curso', 'informacion sobre el curso',
            'informacion del curso', 'detalles del curso', 'datos del curso',
            'silabo de', 'silabos de', 'el curso de', 'la asignatura de',
        ],
    ];

    public function classify(string $question): array
    {
        $normalized = Support::normalize($question);
        $scores     = $this->scoreIntents($normalized, $question);
        $intent     = $this->selectBestIntent($scores);
        $confidence = $this->computeConfidence($scores, $intent);
        $meta       = self::INTENT_MAP[$intent];

        return [
            'intent'            => $intent,
            'visible_intent'    => $meta['visible'],
            'engine'            => $meta['engine'],       // internal only
            'confidence'        => $confidence,
            'collection'        => $this->pickCollection($normalized),
            'requires_chart'    => $meta['requires_chart'],
            'requires_evidence' => $meta['requires_evidence'],
            'requires_export'   => $intent === 'report',
            'reason'            => $this->buildReason($intent, $question, $scores),
        ];
    }

    // ─── Private ─────────────────────────────────────────────────────────────

    private function scoreIntents(string $normalized, string $original): array
    {
        $scores = [];
        foreach (self::RULES as $intent => $keywords) {
            $score = 0;
            foreach ($keywords as $kw) {
                if (str_contains($normalized, $kw)) {
                    $score++;
                }
            }
            if ($score > 0) {
                $scores[$intent] = $score;
            }
        }
        return $scores;
    }

    private function selectBestIntent(array $scores): string
    {
        if (empty($scores)) {
            return 'unknown';
        }
        // Priority order for ties
        $priority = [
            'syllabus_generation', 'comparison', 'study_plan',
            'curriculum_grid', 'report', 'dataset_quality',
            'chart', 'statistics', 'semantic_search', 'course_lookup',
        ];
        $best = 'unknown';
        $bestScore = 0;
        foreach ($priority as $intent) {
            $s = $scores[$intent] ?? 0;
            if ($s > $bestScore) {
                $bestScore = $s;
                $best = $intent;
            }
        }
        return $best;
    }

    private function computeConfidence(array $scores, string $intent): float
    {
        if ($intent === 'unknown' || empty($scores)) {
            return 0.0;
        }
        $total = array_sum($scores);
        $top   = $scores[$intent] ?? 0;
        $base  = $total > 0 ? $top / $total : 0.0;
        return round(min(0.99, 0.55 + ($base * 0.44)), 2);
    }

    private function pickCollection(string $normalized): ?string
    {
        if (str_contains($normalized, 'bibliografia') || str_contains($normalized, 'referencia') || str_contains($normalized, 'libro')) {
            return 'silabos_bibliografia';
        }
        if (str_contains($normalized, 'competencia') || str_contains($normalized, 'resultado') || str_contains($normalized, 'aprendizaje')) {
            return 'silabos_competencias';
        }
        if (str_contains($normalized, 'sumilla') || str_contains($normalized, 'descripcion')) {
            return 'silabos_sumillas';
        }
        if (str_contains($normalized, 'contenido') || str_contains($normalized, 'unidad') || str_contains($normalized, 'tema')) {
            return 'silabos_contenidos';
        }
        return null;
    }

    private function buildReason(string $intent, string $question, array $scores): string
    {
        $map = [
            'chart'              => 'La solicitud pide visualizar datos como gráfico.',
            'statistics'         => 'La solicitud pide datos numéricos o listados estructurados.',
            'semantic_search'    => 'La solicitud busca contenido curricular específico en los sílabos.',
            'course_lookup'      => 'La solicitud pide información detallada de un curso.',
            'comparison'         => 'La solicitud compara dos o más cursos o elementos.',
            'syllabus_generation'=> 'La solicitud pide crear o diseñar un sílabo nuevo.',
            'study_plan'         => 'La solicitud pide construir un plan de estudios.',
            'curriculum_grid'    => 'La solicitud pide revisar o mostrar la malla curricular.',
            'report'             => 'La solicitud pide generar un informe o reporte.',
            'dataset_quality'    => 'La solicitud revisa la calidad o completitud de los datos.',
            'unknown'            => 'No se pudo determinar la intención con suficiente confianza.',
        ];
        return $map[$intent] ?? 'Intención procesada correctamente.';
    }
}
