<?php
final class AssistantController
{
    public function ollamaHealth(): void
    {
        Support::requireAuth();
        Support::json((new OllamaClient())->health());
    }

    public function chat(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $message = trim((string)($data['message'] ?? ''));
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));
        $contextQuery = trim((string)($data['context_query'] ?? $message));
        if ($message === '') {
            Support::json(['ok' => false, 'message' => 'Escribe una consulta.'], 422);
            return;
        }

        $repo = new SyllabusRepository();
        $context = $repo->contextForPrompt($contextQuery, 6);
        $prompt = $this->buildPrompt($message, $context, false);
        $result = (new OllamaClient())->generate($prompt, $model);
        $response = (string)($result['response'] ?? '');
        $this->saveRun((int)$user['id'], $model, 'chat', $message, $response, $context);

        Support::json(['ok' => true, 'model' => $model, 'response' => $response, 'context' => $context]);
    }

    private function intInRange($value, int $min, int $max, int $default): int
    {
        $n = filter_var($value, FILTER_VALIDATE_INT);

        if ($n === false || $n === null) {
            $n = $default;
        }

        $n = (int)$n;

        if ($n < $min) {
            return $min;
        }

        if ($n > $max) {
            return $max;
        }

        return $n;
    }

    private function resolveSyllabusStartDate(string $raw): DateTime
    {
        $tz = new DateTimeZone('America/Lima');

        if ($raw !== '') {
            $date = DateTime::createFromFormat('Y-m-d', $raw, $tz);
            $errors = DateTime::getLastErrors();

            $valid = $date instanceof DateTime;

            if (is_array($errors)) {
                $valid = $valid && (int)$errors['warning_count'] === 0 && (int)$errors['error_count'] === 0;
            }

            if ($valid) {
                $date->setTime(0, 0, 0);
                return $date;
            }
        }

        // Si no se envía fecha, se propone el lunes más cercano.
        $date = new DateTime('now', $tz);
        $date->setTime(0, 0, 0);

        if ((int)$date->format('N') !== 1) {
            $date->modify('next monday');
        }

        return $date;
    }

    private function buildSyllabusUnits(int $weeks): array
    {
        $unitCount = (int)ceil($weeks / 4);

        if ($unitCount < 1) {
            $unitCount = 1;
        }

        if ($unitCount > 5) {
            $unitCount = 5;
        }

        // Para 16 semanas: 4 unidades de 4 semanas.
        if ($weeks === 16) {
            $unitCount = 4;
        }

        $base = intdiv($weeks, $unitCount);
        $extra = $weeks % $unitCount;

        $units = [];
        $start = 1;

        for ($i = 1; $i <= $unitCount; $i++) {
            $length = $base + ($i <= $extra ? 1 : 0);
            $end = $start + $length - 1;

            $units[] = [
                'unit' => $i,
                'label' => 'Unidad ' . $this->romanNumber($i),
                'start_week' => $start,
                'end_week' => $end,
                'weeks_count' => $length,
            ];

            $start = $end + 1;
        }

        return $units;
    }

    private function buildSyllabusCalendar(DateTime $startDate, int $weeks, int $sessionsPerWeek, array $units): array
    {
        $rows = [];
        $sessionOffsets = $this->sessionDayOffsets($sessionsPerWeek);

        $finalEndDate = null;

        for ($week = 1; $week <= $weeks; $week++) {
            $weekStart = clone $startDate;
            $weekStart->modify('+' . (($week - 1) * 7) . ' days');

            $weekEnd = clone $weekStart;
            $weekEnd->modify('+6 days');

            if ($week === $weeks) {
                $finalEndDate = clone $weekEnd;
            }

            $sessions = [];

            for ($i = 0; $i < count($sessionOffsets); $i++) {
                $sessionDate = clone $weekStart;
                $sessionDate->modify('+' . $sessionOffsets[$i] . ' days');

                $sessions[] = [
                    'session' => $i + 1,
                    'date' => $sessionDate->format('Y-m-d'),
                    'date_label' => $sessionDate->format('d/m/Y'),
                    'label' => 'Semana ' . $week . ' - Sesión ' . ($i + 1),
                ];
            }

            $rows[] = [
                'week' => $week,
                'unit' => $this->unitForWeek($units, $week),
                'start_date' => $weekStart->format('Y-m-d'),
                'start_label' => $weekStart->format('d/m/Y'),
                'end_date' => $weekEnd->format('Y-m-d'),
                'end_label' => $weekEnd->format('d/m/Y'),
                'sessions' => $sessions,
            ];
        }

        return [
            'start_date' => $startDate->format('Y-m-d'),
            'start_label' => $startDate->format('d/m/Y'),
            'end_date' => $finalEndDate ? $finalEndDate->format('Y-m-d') : $startDate->format('Y-m-d'),
            'end_label' => $finalEndDate ? $finalEndDate->format('d/m/Y') : $startDate->format('d/m/Y'),
            'weeks' => $weeks,
            'sessions_per_week' => $sessionsPerWeek,
            'week_rows' => $rows,
        ];
    }

    private function buildSyllabusEvaluationDates(array $calendar, array $units, int $weeks): array
    {
        $weekMap = [];

        foreach ($calendar['week_rows'] as $row) {
            $weekMap[(int)$row['week']] = $row;
        }

        $unitCount = max(1, count($units));
        $productWeight = round(40 / $unitCount, 2);
        $resultWeight = round(30 / $unitCount, 2);

        $products = [];
        $results = [];

        foreach ($units as $unit) {
            $endWeek = (int)$unit['end_week'];
            $row = $weekMap[$endWeek] ?? null;
            $date = $row ? $this->lastSessionDateFromWeekRow($row) : null;

            $products[] = [
                'unit' => (int)$unit['unit'],
                'week' => $endWeek,
                'date' => $date,
                'weight' => $productWeight,
                'scale' => '0-20',
                'type' => 'Producto de unidad',
            ];

            $results[] = [
                'unit' => (int)$unit['unit'],
                'week' => $endWeek,
                'date' => $date,
                'weight' => $resultWeight,
                'scale' => '0-20',
                'type' => 'Evaluación de resultado de aprendizaje',
            ];
        }

        $lastWeek = $weekMap[$weeks] ?? null;
        $competencyDate = $lastWeek ? $this->lastSessionDateFromWeekRow($lastWeek) : null;

        return [
            'weighting' => [
                'unit_products_total' => 40,
                'learning_results_total' => 30,
                'course_competency_total' => 30,
                'final_formula' => 'NF = Σ(Nota × Peso/100). Todas las notas se registran en escala vigesimal de 0 a 20.',
            ],
            'unit_products' => $products,
            'learning_results' => $results,
            'course_competency' => [
                'week' => $weeks,
                'date' => $competencyDate,
                'weight' => 30,
                'scale' => '0-20',
                'type' => 'Evaluación integradora de competencia del curso',
            ],
        ];
    }

    private function sessionDayOffsets(int $sessionsPerWeek): array
    {
        if ($sessionsPerWeek <= 1) {
            return [0]; // lunes
        }

        if ($sessionsPerWeek === 2) {
            return [0, 2]; // lunes, miércoles
        }

        if ($sessionsPerWeek === 3) {
            return [0, 2, 4]; // lunes, miércoles, viernes
        }

        if ($sessionsPerWeek === 4) {
            return [0, 1, 2, 4]; // lunes, martes, miércoles, viernes
        }

        return [0, 1, 2, 3, 4]; // lunes a viernes
    }

    private function unitForWeek(array $units, int $week): int
    {
        foreach ($units as $unit) {
            if ($week >= (int)$unit['start_week'] && $week <= (int)$unit['end_week']) {
                return (int)$unit['unit'];
            }
        }

        return 1;
    }

    private function lastSessionDateFromWeekRow(array $row): ?string
    {
        $sessions = $row['sessions'] ?? [];

        if (is_array($sessions) && count($sessions) > 0) {
            $last = $sessions[count($sessions) - 1];
            return $last['date'] ?? null;
        }

        return $row['end_date'] ?? null;
    }

    private function romanNumber(int $number): string
    {
        $map = [
            1 => 'I',
            2 => 'II',
            3 => 'III',
            4 => 'IV',
            5 => 'V',
            6 => 'VI',
        ];

        return $map[$number] ?? (string)$number;
    }



    private function buildStrictSyllabusPrompt(array $meta, array $context, array $units, array $calendar, array $evaluationDates): string
    {
        $metaJson = json_encode($meta, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        $unitsJson = json_encode($units, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        $calendarJson = json_encode($calendar['week_rows'], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        $evaluationJson = json_encode($evaluationDates, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        $contextText = $this->syllabusContextToPrompt($context);

        $today = date('Y-m-d');

        return
            "Eres JoMelAi Curriculista UPeU, especialista en diseño curricular universitario, sílabos por competencias, evaluación académica y planificación semestral.\n\n" .

            "OBJETIVO:\n" .
            "Genera un sílabo académico preliminar completo, formal, editable y listo para revisión de comité curricular.\n\n" .

            "REGLAS CRÍTICAS OBLIGATORIAS:\n" .
            "1. Responde SOLO en Markdown. No uses JSON en la respuesta final.\n" .
            "2. No saludes, no expliques el proceso y no agregues comentarios fuera del sílabo.\n" .
            "3. No uses placeholders tipo [Insertar]. Si falta un dato, usa una redacción académica razonable o escribe 'Por completar por el comité curricular'.\n" .
            "4. Respeta exactamente el número de semanas indicado.\n" .
            "5. No crees semanas adicionales. Si hay más de una sesión por semana, las sesiones deben estar dentro de la misma semana.\n" .
            "6. Las unidades deben cubrir todas las semanas una sola vez, sin saltos ni duplicidades.\n" .
            "7. Cada unidad debe tener resultado de aprendizaje de unidad y producto de unidad.\n" .
            "8. Cada sesión debe tener tema, propósito, actividad, evidencia y relación con resultado de aprendizaje.\n" .
            "9. Todas las evaluaciones deben tener fecha y usar sistema numérico vigesimal de 0 a 20.\n" .
            "10. La ponderación total de evaluación debe sumar 100%.\n" .
            "11. Las referencias bibliográficas deben ser académicas, científicas o de editoriales universitarias/reconocidas.\n" .
            "12. No inventes DOI. Si no conoces un DOI real, escribe 'DOI no identificado'.\n" .
            "13. Los enlaces web deben ser académicos, oficiales, editoriales, repositorios, open textbooks o universidades. No uses blogs genéricos como fuente principal.\n" .
            "14. El contenido debe ser suficientemente completo; no cortes la respuesta.\n\n" .

            "DATOS DEL CURSO:\n" .
            $metaJson . "\n\n" .

            "DISTRIBUCIÓN OBLIGATORIA DE UNIDADES:\n" .
            $unitsJson . "\n\n" .

            "CALENDARIO OBLIGATORIO DE SEMANAS Y SESIONES:\n" .
            "Usa estas semanas y fechas. No inventes semanas fuera de este calendario.\n" .
            $calendarJson . "\n\n" .

            "FECHAS Y PESOS DE EVALUACIÓN OBLIGATORIOS:\n" .
            $evaluationJson . "\n\n" .

            "CONTEXTO INSTITUCIONAL / SÍLABOS RELACIONADOS:\n" .
            $contextText . "\n\n" .

            "INSTRUCCIONES DE PLANTILLA:\n" .
            CurriculumGuidelines::syllabusTemplateInstruction() . "\n\n" .

            "ESTRUCTURA OBLIGATORIA DE LA RESPUESTA MARKDOWN:\n" .
            "# Sílabo Preliminar: " . $meta['course'] . "\n\n" .

            "## 1. Datos generales\n" .
            "Incluye curso, programa, créditos, ciclo, modalidad, semanas, sesiones por semana, fecha de inicio, fecha de fin y escala de evaluación.\n\n" .

            "## 2. Sumilla\n" .
            "Redacta una sumilla académica completa en uno o dos párrafos.\n\n" .

            "## 3. Competencia del curso\n" .
            "Formula una competencia clara, observable e integradora.\n\n" .

            "## 4. Resultados de aprendizaje del curso\n" .
            "Incluye entre 4 y 6 resultados de aprendizaje medibles.\n\n" .

            "## 5. Organización por unidades\n" .
            "Usa una tabla con: Unidad, semanas, fechas, resultado de aprendizaje de unidad, contenidos centrales y producto de unidad.\n\n" .

            "## 6. Programación de sesiones\n" .
            "Usa una tabla. Debe respetar exactamente el calendario entregado. Columnas obligatorias: Semana, Fechas de la semana, Unidad, Sesión, Fecha de sesión, Tema, Propósito de la sesión, Actividad de aprendizaje, Evidencia.\n\n" .

            "## 7. Evaluaciones de producto de unidad\n" .
            "Usa una tabla con: Unidad, Producto evaluable, Fecha, Criterios, Instrumento, Peso, Escala.\n\n" .

            "## 8. Evaluaciones de resultados de aprendizaje\n" .
            "Usa una tabla con: Resultado de aprendizaje, Unidad, Fecha, Evidencia, Instrumento, Peso, Escala.\n\n" .

            "## 9. Evaluación de competencia del curso\n" .
            "Describe la evaluación integradora final de competencia. Incluye fecha, producto integrador, criterios, instrumento, peso y escala.\n\n" .

            "## 10. Sistema de calificación vigesimal\n" .
            "Explica que la escala es de 0 a 20. Incluye fórmula de nota final ponderada y tabla de pesos. Fecha de generación: " . $today . ".\n\n" .

            "## 11. Estrategias metodológicas\n" .
            "Incluye estrategias activas, trabajo autónomo, acompañamiento docente y uso de recursos digitales.\n\n" .

            "## 12. Referencias bibliográficas validadas científicamente\n" .
            "Incluye al menos 8 referencias. Usa formato académico. Para cada una indica: Autor, año, título, editorial/revista, tipo de fuente, DOI o URL si es conocido, y utilidad para el curso.\n\n" .

            "## 13. Enlaces académicos de internet\n" .
            "Incluye enlaces de apoyo académico confiables, preferentemente universidades, repositorios, libros abiertos, organismos oficiales o editoriales. No uses Wikipedia como fuente principal.\n\n" .

            "## 14. Observaciones para revisión curricular\n" .
            "Incluye advertencia breve: propuesta preliminar, requiere validación docente y aprobación del comité curricular.\n\n" .

            "Genera ahora el sílabo completo en Markdown.";
    }

    private function syllabusContextToPrompt(array $context): string
    {
        if (empty($context)) {
            return "No se encontraron sílabos institucionales cercanos. Generar propuesta base con criterio académico.";
        }

        $out = '';

        foreach ($context as $i => $row) {
            $out .= "FUENTE " . ($i + 1) . ":\n";
            $out .= "Curso: " . (string)($row['curso'] ?? '') . "\n";
            $out .= "Programa: " . (string)($row['programa'] ?? '') . "\n";
            $out .= "Código: " . (string)($row['codigo'] ?? '') . "\n";
            $out .= "Ciclo: " . (string)($row['ciclo'] ?? '') . "\n";
            $out .= "Créditos: " . (string)($row['creditos'] ?? '') . "\n";
            $out .= "Competencia: " . $this->limitSyllabusText((string)($row['competencia'] ?? ''), 300) . "\n";
            $out .= "Sumilla: " . $this->limitSyllabusText((string)($row['sumilla'] ?? ''), 300) . "\n";
            $out .= "Contenidos: " . $this->limitSyllabusText((string)($row['contenidos'] ?? ''), 450) . "\n";
            $out .= "Evaluación: " . $this->limitSyllabusText((string)($row['evaluacion'] ?? ''), 250) . "\n";
            $out .= "Bibliografía: " . $this->limitSyllabusText((string)($row['bibliografia'] ?? ''), 300) . "\n\n";
        }

        return $this->limitSyllabusText($out, 3500);
    }

    private function limitSyllabusText(string $text, int $max): string
    {
        $text = trim(preg_replace('/\s+/u', ' ', $text));

        if ($text === '') {
            return '';
        }

        if (function_exists('mb_strlen') && function_exists('mb_substr')) {
            if (mb_strlen($text, 'UTF-8') <= $max) {
                return $text;
            }

            return mb_substr($text, 0, $max, 'UTF-8') . '...';
        }

        if (strlen($text) <= $max) {
            return $text;
        }

        return substr($text, 0, $max) . '...';
    }

    private function cleanSyllabusResponse(string $response): string
    {
        $response = trim($response);

        $response = preg_replace('/^```(?:markdown|md)?\s*/i', '', $response);
        $response = preg_replace('/\s*```$/', '', $response);

        return trim($response);
    }

    public function generateSyllabus(): void
    {
        ini_set('max_execution_time', '300');

        $user = Support::requireAuth();
        $data = Support::readJson();

        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));

        $course = trim((string)($data['course'] ?? ''));
        $program = trim((string)($data['program'] ?? ''));
        $credits = trim((string)($data['credits'] ?? ''));
        $cycle = trim((string)($data['cycle'] ?? ''));
        $modality = trim((string)($data['modality'] ?? 'Presencial'));
        $profile = trim((string)($data['graduate_profile'] ?? ''));
        $competency = trim((string)($data['competency'] ?? ''));

        $weeks = $this->intInRange($data['weeks'] ?? 16, 8, 20, 16);
        $sessionsPerWeek = $this->intInRange($data['sessions_per_week'] ?? 1, 1, 5, 1);

        $startDateRaw = trim((string)($data['start_date'] ?? ''));
        $startDate = $this->resolveSyllabusStartDate($startDateRaw);

        if ($course === '') {
            Support::json([
                'ok' => false,
                'message' => 'El nombre del curso es obligatorio.'
            ], 422);
            return;
        }

        $units = $this->buildSyllabusUnits($weeks);
        $calendar = $this->buildSyllabusCalendar($startDate, $weeks, $sessionsPerWeek, $units);
        $evaluationDates = $this->buildSyllabusEvaluationDates($calendar, $units, $weeks);

        $contextQuery = trim($course . ' ' . $program . ' ' . $competency . ' ' . $profile);
        $context = (new SyllabusRepository())->contextForPrompt($contextQuery, 3);

        $meta = [
            'course' => $course,
            'program' => $program !== '' ? $program : 'Por completar',
            'credits' => $credits !== '' ? $credits : 'Por completar',
            'cycle' => $cycle !== '' ? $cycle : 'Por completar',
            'modality' => $modality !== '' ? $modality : 'Presencial',
            'weeks' => $weeks,
            'sessions_per_week' => $sessionsPerWeek,
            'start_date' => $calendar['start_date'],
            'end_date' => $calendar['end_date'],
            'graduate_profile' => $profile !== '' ? $profile : 'Por completar por el comité curricular',
            'competency' => $competency !== '' ? $competency : 'Debe formularse a partir del propósito del curso y el perfil de egreso',
            'evaluation_scale' => 'Sistema numérico vigesimal: 0 a 20',
        ];

        $prompt = $this->buildStrictSyllabusPrompt($meta, $context, $units, $calendar, $evaluationDates);
        error_log('[SYLLABUS_DEBUG] model=' . $model);
        error_log('[SYLLABUS_DEBUG] course=' . $course);
        error_log('[SYLLABUS_DEBUG] prompt_chars=' . strlen($prompt ?? ''));
        error_log('[SYLLABUS_DEBUG] context_count=' . count($context ?? []));
        $result = (new OllamaClient())->generate($prompt, $model, [
            'temperature' => 0.15,
            'top_p' => 0.9,
            'repeat_penalty' => 1.08,

            // Importante para evitar respuestas cortadas como "El est..."
            'num_ctx' => 2048,
            'num_predict' => 1000,
        ]);

        $response = $this->cleanSyllabusResponse((string)($result['response'] ?? ''));

        if ($response === '') {
            Support::json([
                'ok' => false,
                'message' => 'El modelo no devolvió contenido para el sílabo.',
                'model' => $model,
                'raw' => $result,
            ], 422);
            return;
        }

        $message = 'Generar sílabo académico preliminar: ' . json_encode($meta, JSON_UNESCAPED_UNICODE);

        $this->saveRun(
            (int)$user['id'],
            $model,
            'generate_syllabus',
            $message,
            $response,
            $context
        );

        Support::json([
            'ok' => true,
            'model' => $model,
            'response' => $response,
            'context' => $context,
            'artifact' => [
                'type' => 'syllabus',
                'format' => 'markdown',
                'meta' => $meta,
                'units' => $units,
                'calendar' => $calendar,
                'evaluation_dates' => $evaluationDates,
            ],
        ]);
    }

    public function pythonReportScript(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));
        $csvPath = trim((string)($data['csv_path'] ?? 'silabos.csv'));
        $goal = trim((string)($data['goal'] ?? 'Generar un reporte curricular con gráficos por programa, créditos y presencia de resultados de aprendizaje.'));

        $message = "Actúa como especialista en datos académicos. Genera un script de Python 3, limpio y comentado, que lea el CSV grande ubicado en '{$csvPath}' por chunks con pandas, produzca métricas curriculares y gráficos con matplotlib, y guarde un PDF o PNGs de reporte. Objetivo: {$goal}. No ejecutes nada; entrega solo el código y una breve explicación de uso.";
        $prompt = $this->buildPrompt($message, [], false);
        $result = (new OllamaClient())->generate($prompt, $model, ['temperature' => 0.15]);
        $response = (string)($result['response'] ?? '');
        $this->saveRun((int)$user['id'], $model, 'python_report_script', $message, $response, []);
        Support::json(['ok' => true, 'model' => $model, 'response' => $response]);
    }

    private function buildPrompt(string $message, array $context, bool $syllabus): string
    {
        $ctx = json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        $task = $syllabus ? CurriculumGuidelines::syllabusTemplateInstruction() : '';
        return CurriculumGuidelines::systemPrompt() . "\n\nContexto recuperado desde sílabos institucionales indexados:\n" . $ctx . "\n\nInstrucción adicional:\n" . $task . "\n\nSolicitud del usuario:\n" . $message;
    }

    private function saveRun(int $userId, string $model, string $taskType, string $prompt, string $response, array $context): void
    {
        $stmt = Database::pdo()->prepare('INSERT INTO assistant_runs (user_id, model, task_type, prompt, response, context_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([$userId, $model, $taskType, $prompt, $response, json_encode($context, JSON_UNESCAPED_UNICODE), Support::now()]);
    }
}
