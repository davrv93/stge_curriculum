<?php
final class CurriculumController
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::pdo();
    }

    public function framework(): void
    {
        Support::requireAuth();
        Support::json([
            'ok' => true,
            'wizard' => [
                ['step' => 1, 'title' => 'Proyecto curricular', 'description' => 'Define programa, facultad, modalidad, duración, créditos meta y propósito formativo.'],
                ['step' => 2, 'title' => 'Perfil de egreso', 'description' => 'Declara competencias profesionales, formación integral, servicio y ética desde identidad adventista.'],
                ['step' => 3, 'title' => 'Malla curricular', 'description' => 'Distribuye cursos por ciclo, créditos, área formativa y prerrequisitos.'],
                ['step' => 4, 'title' => 'Mapa de competencias', 'description' => 'Relaciona cursos con competencias, resultados de aprendizaje y evidencias.'],
                ['step' => 5, 'title' => 'Plan de estudios', 'description' => 'Revisa coherencia vertical/horizontal, carga crediticia y progresión académica.'],
                ['step' => 6, 'title' => 'Versión y aprobación', 'description' => 'Guarda versión, compara cambios y publica la versión aprobada.'],
            ],
            'principles' => [
                'Diseño inverso: resultados, evidencias y actividades alineadas.',
                'Resultados observables usando verbos medibles.',
                'Progresión gradual por ciclos: fundamentos, desarrollo, integración y práctica profesional.',
                'Integración fe-aprendizaje sobria: cosmovisión bíblico-cristiana, servicio, ética, dignidad humana, mayordomía y vida saludable.',
                'No sustituye la validación formal de comité curricular, dirección de escuela ni vicerrectorado académico.',
            ],
        ]);
    }

    public function projects(): void
    {
        Support::requireAuth();
        $rows = $this->pdo->query('SELECT * FROM curriculum_projects ORDER BY updated_at DESC, id DESC')->fetchAll();
        foreach ($rows as &$row) {
            $row['version_count'] = (int)$this->pdo->query('SELECT COUNT(*) AS c FROM curriculum_versions WHERE project_id = ' . (int)$row['id'])->fetch()['c'];
        }
        Support::json(['ok' => true, 'projects' => $rows]);
    }

    public function createProject(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $program = trim((string)($data['program'] ?? ''));
        $faculty = trim((string)($data['faculty'] ?? ''));
        if ($program === '' || $faculty === '') {
            Support::json(['ok' => false, 'message' => 'Facultad y programa son obligatorios.'], 422);
            return;
        }
        $cycles = max(1, min(14, (int)($data['cycles'] ?? 10)));
        $targetCredits = max(1, min(300, (int)($data['target_credits'] ?? 200)));
        $now = Support::now();
        $stmt = $this->pdo->prepare('INSERT INTO curriculum_projects (faculty, program, degree, modality, cycles, target_credits, profile_text, description, status, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([
            $faculty,
            $program,
            trim((string)($data['degree'] ?? 'Bachiller / Título profesional')),
            trim((string)($data['modality'] ?? 'Presencial')),
            $cycles,
            $targetCredits,
            trim((string)($data['profile_text'] ?? '')),
            trim((string)($data['description'] ?? '')),
            'draft',
            (int)$user['id'],
            $now,
            $now,
        ]);
        $id = (int)$this->pdo->lastInsertId();
        $project = $this->getProjectRow($id);
        Support::json(['ok' => true, 'project' => $project]);
    }

    public function generatePlan(): void
    {
        $started = microtime(true);
        $user = Support::requireAuth();
        $data = Support::readJson();
        $project = null;
        $projectId = (int)($data['project_id'] ?? 0);
        if ($projectId > 0) {
            $project = $this->getProjectRow($projectId);
        }

        $program = trim((string)($data['program'] ?? ($project['program'] ?? 'Ingeniería de Sistemas')));
        $faculty = trim((string)($data['faculty'] ?? ($project['faculty'] ?? 'Ingeniería y Arquitectura')));
        $cycles = max(1, min(14, (int)($data['cycles'] ?? ($project['cycles'] ?? 10))));
        $targetCredits = max(1, min(300, (int)($data['target_credits'] ?? ($project['target_credits'] ?? 200))));
        $profile = trim((string)($data['profile_text'] ?? ($project['profile_text'] ?? '')));
        $emphasis = trim((string)($data['emphasis'] ?? 'competencias profesionales, investigación formativa, servicio, ética y responsabilidad social'));
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));
        $useAi = (bool)($data['use_ai'] ?? true);
        $mode = trim((string)($data['mode'] ?? 'fast'));

        $cacheKey = $this->planCacheKey($faculty, $program, $cycles, $targetCredits, $profile, $emphasis, $mode, $useAi, $model);
        if ((bool)($data['use_cache'] ?? true)) {
            $cached = $this->getPlanCache($cacheKey);
            if ($cached) {
                $cached['cached'] = true;
                $cached['elapsed_ms'] = (int)round((microtime(true) - $started) * 1000);
                Support::json($cached);
                return;
            }
        }

        $reference = $this->curriculumReferenceFor($program, $faculty);
        $plan = $this->buildBasePlan($faculty, $program, $cycles, $targetCredits, $profile, $emphasis);
        $plan = $this->enrichPlanWithReference($plan, $reference);
        $plan['generation_strategy'] = 'deterministic_template_first';
        $plan['performance_budget_seconds'] = 15;

        $markdown = $this->planMarkdown($plan);
        $aiNote = '';
        $aiTimedOut = false;
        $aiUsed = false;

        if ($useAi) {
            try {
                $prompt = $this->buildPlanReviewPromptFast($faculty, $program, $cycles, $targetCredits, $profile, $emphasis, $plan, $reference);
                $result = (new OllamaClient())->generateFast($prompt, $model, [], (int)Support::config('ollama_plan_timeout'));
                $aiNote = trim((string)($result['response'] ?? ''));
                $aiUsed = $aiNote !== '';
                if ($aiNote !== '') {
                    $markdown .= "\n\n## Revisión curricular asistida por IA rápida\n\n" . $aiNote;
                }
            } catch (Throwable $e) {
                $aiTimedOut = true;
                $aiNote = 'La revisión generativa superó el presupuesto de tiempo o no respondió. Se entregó el plan determinístico enriquecido para no bloquear la API. Detalle: ' . $e->getMessage();
                $markdown .= "\n\n## Nota operativa\n\n" . $aiNote;
            }
        }

        $payload = [
            'ok' => true,
            'plan_json' => $plan,
            'markdown' => $markdown,
            'model' => $model,
            'ai_note' => $aiNote,
            'ai_used' => $aiUsed,
            'ai_timed_out' => $aiTimedOut,
            'cached' => false,
            'elapsed_ms' => (int)round((microtime(true) - $started) * 1000),
            'next_step' => $aiTimedOut ? 'Puedes pedir una revisión profunda por secciones, pero la generación del plan no queda bloqueada.' : 'Plan generado dentro del presupuesto rápido.',
        ];

        $this->putPlanCache($cacheKey, $payload, $program, $faculty);
        $this->audit((int)$user['id'], 'generate_plan_fast', [
            'project_id' => $projectId ?: null,
            'program' => $program,
            'model' => $model,
            'used_ai' => $aiUsed,
            'ai_timed_out' => $aiTimedOut,
            'elapsed_ms' => $payload['elapsed_ms'],
        ]);

        Support::json($payload);
    }

    private function planCacheKey(string $faculty, string $program, int $cycles, int $credits, string $profile, string $emphasis, string $mode, bool $useAi, string $model): string
    {
        return hash('sha256', json_encode([$faculty, $program, $cycles, $credits, $profile, $emphasis, $mode, $useAi, $model], JSON_UNESCAPED_UNICODE));
    }

    private function getPlanCache(string $cacheKey): ?array
    {
        $stmt = $this->pdo->prepare('SELECT payload_json FROM curriculum_generation_cache WHERE cache_key = ? AND expires_at > ? LIMIT 1');
        $stmt->execute([$cacheKey, Support::now()]);
        $row = $stmt->fetch();
        if (!$row) return null;
        $payload = json_decode((string)$row['payload_json'], true);
        return is_array($payload) ? $payload : null;
    }

    private function putPlanCache(string $cacheKey, array $payload, string $program, string $faculty): void
    {
        $ttl = max(300, (int)Support::config('curriculum_cache_ttl_seconds'));
        $now = Support::now();
        $expires = gmdate('Y-m-d H:i:s', time() + $ttl);
        $stmt = $this->pdo->prepare('INSERT OR REPLACE INTO curriculum_generation_cache(cache_key, request_hash, program, faculty, payload_json, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([$cacheKey, $cacheKey, $program, $faculty, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), $now, $expires]);
    }

    private function curriculumReferenceFor(string $program, string $faculty): array
    {
        $normProgram = Support::normalize($program);
        $ref = [
            'matched_malla' => null,
            'course_names' => [],
            'areas' => [],
            'notes' => [],
        ];
        $dir = __DIR__ . '/../resources/curriculum_reference/mallas';
        if (is_dir($dir)) {
            foreach (glob($dir . '/*.md') ?: [] as $file) {
                $base = Support::normalize(basename($file, '.md'));
                $score = 0;
                foreach (explode('_', str_replace(['malla', 'upeu'], '', $base)) as $token) {
                    $token = trim($token, '- ');
                    if ($token !== '' && str_contains($normProgram, $token)) $score++;
                }
                if ($score > 0 && (!$ref['matched_malla'] || $score > ($ref['_score'] ?? 0))) {
                    $text = (string)file_get_contents($file);
                    $ref['matched_malla'] = basename($file);
                    $ref['_score'] = $score;
                    $ref['notes'][] = Support::strLimit($text, 2500);
                    preg_match_all('/\|\s*([^|\n]{4,80})\s*\|\s*(\d+)\s*\|/u', $text, $m);
                    foreach (($m[1] ?? []) as $name) {
                        $name = trim(strip_tags($name));
                        if ($name !== '' && !in_array($name, $ref['course_names'], true)) $ref['course_names'][] = $name;
                    }
                    if (count($ref['course_names']) > 40) $ref['course_names'] = array_slice($ref['course_names'], 0, 40);
                }
            }
        }
        unset($ref['_score']);
        return $ref;
    }

    private function enrichPlanWithReference(array $plan, array $reference): array
    {
        if (empty($reference['course_names'])) {
            return $plan;
        }
        $names = $reference['course_names'];
        $i = 0;
        foreach ($plan['cycles'] as &$cycle) {
            foreach ($cycle['courses'] as &$course) {
                if ($i < count($names) && !str_contains(Support::normalize((string)$course['area']), 'identidad')) {
                    $course['name'] = $names[$i];
                    $course['outcomes'] = [$this->courseOutcome($course['name'], (string)$course['area'])];
                    $i++;
                }
            }
        }
        $plan['reference_source'] = $reference['matched_malla'] ?? 'plantilla curricular interna';
        return $plan;
    }

    public function saveVersion(array $params): void
    {
        $user = Support::requireAuth();
        $projectId = (int)($params['id'] ?? 0);
        $project = $this->getProjectRow($projectId);
        if (!$project) {
            Support::json(['ok' => false, 'message' => 'Proyecto curricular no encontrado.'], 404);
            return;
        }
        $data = Support::readJson();
        $planJson = $data['plan_json'] ?? null;
        if (!is_array($planJson)) {
            Support::json(['ok' => false, 'message' => 'plan_json es obligatorio para guardar la versión.'], 422);
            return;
        }
        $versionNo = $this->nextVersionNo($projectId);
        $now = Support::now();
        $title = trim((string)($data['title'] ?? ('Versión ' . $versionNo . ' - ' . $project['program'])));
        $stmt = $this->pdo->prepare('INSERT INTO curriculum_versions (project_id, version_no, title, status, plan_json, plan_markdown, change_summary, created_by, created_at, published_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([
            $projectId,
            $versionNo,
            $title,
            'draft',
            json_encode($planJson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            (string)($data['plan_markdown'] ?? ''),
            trim((string)($data['change_summary'] ?? 'Nueva versión generada desde wizard curricular.')),
            (int)$user['id'],
            $now,
            null,
        ]);
        $this->pdo->prepare('UPDATE curriculum_projects SET updated_at = ? WHERE id = ?')->execute([$now, $projectId]);
        $version = $this->getVersionRow((int)$this->pdo->lastInsertId());
        $this->audit((int)$user['id'], 'save_version', ['project_id' => $projectId, 'version_id' => $version['id'], 'version_no' => $versionNo]);
        Support::json(['ok' => true, 'version' => $version]);
    }

    public function versions(array $params): void
    {
        Support::requireAuth();
        $projectId = (int)($params['id'] ?? 0);
        $stmt = $this->pdo->prepare('SELECT * FROM curriculum_versions WHERE project_id = ? ORDER BY version_no DESC, id DESC');
        $stmt->execute([$projectId]);
        $versions = $stmt->fetchAll();
        foreach ($versions as &$v) {
            $v['plan_json'] = json_decode((string)$v['plan_json'], true);
        }
        Support::json(['ok' => true, 'versions' => $versions]);
    }

    public function showVersion(array $params): void
    {
        Support::requireAuth();
        $version = $this->getVersionRow((int)($params['id'] ?? 0));
        if (!$version) {
            Support::json(['ok' => false, 'message' => 'Versión no encontrada.'], 404);
            return;
        }
        Support::json(['ok' => true, 'version' => $version, 'matrix' => $this->matrixFromPlan($version['plan_json'])]);
    }

    public function publishVersion(array $params): void
    {
        $user = Support::requireAuth();
        $version = $this->getVersionRow((int)($params['id'] ?? 0));
        if (!$version) {
            Support::json(['ok' => false, 'message' => 'Versión no encontrada.'], 404);
            return;
        }
        $now = Support::now();
        $this->pdo->prepare('UPDATE curriculum_versions SET status = ? WHERE project_id = ?')->execute(['archived', (int)$version['project_id']]);
        $this->pdo->prepare('UPDATE curriculum_versions SET status = ?, published_at = ? WHERE id = ?')->execute(['published', $now, (int)$version['id']]);
        $this->pdo->prepare('UPDATE curriculum_projects SET status = ?, updated_at = ? WHERE id = ?')->execute(['published', $now, (int)$version['project_id']]);
        $this->audit((int)$user['id'], 'publish_version', ['version_id' => $version['id'], 'project_id' => $version['project_id']]);
        Support::json(['ok' => true, 'version' => $this->getVersionRow((int)$version['id'])]);
    }

    public function compareVersions(array $params): void
    {
        Support::requireAuth();
        $a = $this->getVersionRow((int)($params['a'] ?? 0));
        $b = $this->getVersionRow((int)($params['b'] ?? 0));
        if (!$a || !$b) {
            Support::json(['ok' => false, 'message' => 'Debe seleccionar dos versiones existentes.'], 404);
            return;
        }
        Support::json(['ok' => true, 'comparison' => $this->comparePlans($a, $b)]);
    }

    private function getProjectRow(int $id): ?array
    {
        if ($id <= 0) return null;
        $stmt = $this->pdo->prepare('SELECT * FROM curriculum_projects WHERE id = ? LIMIT 1');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    private function getVersionRow(int $id): ?array
    {
        if ($id <= 0) return null;
        $stmt = $this->pdo->prepare('SELECT * FROM curriculum_versions WHERE id = ? LIMIT 1');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) return null;
        $row['plan_json'] = json_decode((string)$row['plan_json'], true) ?: [];
        return $row;
    }

    private function nextVersionNo(int $projectId): int
    {
        $stmt = $this->pdo->prepare('SELECT COALESCE(MAX(version_no), 0) + 1 AS n FROM curriculum_versions WHERE project_id = ?');
        $stmt->execute([$projectId]);
        return (int)$stmt->fetch()['n'];
    }

    private function buildBasePlan(string $faculty, string $program, int $cycles, int $targetCredits, string $profile, string $emphasis): array
    {
        $isSystems = str_contains(Support::normalize($program), 'sistemas') || str_contains(Support::normalize($program), 'software') || str_contains(Support::normalize($program), 'comput');
        $general = [
            ['COM101','Comunicación Académica',3,'Formación general'],
            ['MAT101','Matemática Básica',4,'Ciencias básicas'],
            ['CRI101','Cosmovisión Bíblico-Cristiana',2,'Identidad institucional'],
            ['VID101','Vida Saludable',2,'Formación integral'],
            ['INV101','Metodología del Trabajo Universitario',2,'Investigación formativa'],
        ];
        $systems = [
            ['SIS101','Fundamentos de Programación',4,'Especialidad'],
            ['SIS102','Algoritmos y Estructuras de Datos',4,'Especialidad'],
            ['SIS103','Arquitectura de Computadoras',3,'Especialidad'],
            ['SIS201','Programación Orientada a Objetos',4,'Especialidad'],
            ['SIS202','Base de Datos I',4,'Especialidad'],
            ['SIS203','Ingeniería de Requisitos',3,'Especialidad'],
            ['SIS301','Desarrollo Web',4,'Especialidad'],
            ['SIS302','Redes y Comunicaciones',3,'Especialidad'],
            ['SIS303','Análisis y Diseño de Sistemas',4,'Especialidad'],
            ['SIS401','Arquitectura de Software',4,'Especialidad'],
            ['SIS402','Inteligencia de Negocios',3,'Especialidad'],
            ['SIS403','Seguridad de la Información',3,'Especialidad'],
            ['SIS501','Gestión de Proyectos de Software',4,'Especialidad'],
            ['SIS502','Computación en la Nube',3,'Especialidad'],
            ['SIS503','Analítica de Datos',4,'Especialidad'],
            ['SIS601','Inteligencia Artificial Aplicada',4,'Especialidad'],
            ['SIS602','Arquitectura Empresarial',3,'Especialidad'],
            ['SIS603','Calidad de Software',3,'Especialidad'],
            ['SIS701','Prácticas Preprofesionales I',4,'Práctica profesional'],
            ['SIS702','Investigación Aplicada I',3,'Investigación formativa'],
            ['SIS801','Prácticas Preprofesionales II',4,'Práctica profesional'],
            ['SIS802','Investigación Aplicada II',3,'Investigación formativa'],
            ['SIS901','Proyecto Integrador Profesional',4,'Integración'],
            ['SIS902','Ética Profesional y Servicio',3,'Formación integral'],
            ['SIS1001','Trabajo de Investigación',4,'Investigación formativa'],
        ];
        $generic = [
            ['ESP101','Fundamentos de la Profesión',4,'Especialidad'],
            ['ESP102','Bases Disciplinares I',4,'Especialidad'],
            ['ESP201','Bases Disciplinares II',4,'Especialidad'],
            ['ESP202','Herramientas Profesionales',3,'Especialidad'],
            ['ESP301','Diseño de Intervenciones Profesionales',4,'Especialidad'],
            ['ESP302','Gestión de Procesos del Área',3,'Especialidad'],
            ['ESP401','Métodos Aplicados de la Profesión',4,'Especialidad'],
            ['ESP402','Seminario de Problemas Contemporáneos',3,'Especialidad'],
            ['ESP501','Proyecto Integrador I',4,'Integración'],
            ['ESP502','Investigación Aplicada I',3,'Investigación formativa'],
            ['ESP601','Proyecto Integrador II',4,'Integración'],
            ['ESP602','Investigación Aplicada II',3,'Investigación formativa'],
            ['ESP701','Práctica Preprofesional I',4,'Práctica profesional'],
            ['ESP801','Práctica Preprofesional II',4,'Práctica profesional'],
            ['ESP901','Ética Profesional y Servicio',3,'Formación integral'],
            ['ESP1001','Trabajo de Investigación',4,'Investigación formativa'],
        ];
        $pool = array_merge($general, $isSystems ? $systems : $generic);
        $perCycle = array_fill(1, $cycles, []);
        $creditTotal = 0;
        $idx = 0;
        foreach ($pool as $course) {
            $cycle = ($idx % $cycles) + 1;
            $code = $course[0];
            $name = $course[1];
            $credits = (int)$course[2];
            $area = $course[3];
            $perCycle[$cycle][] = [
                'code' => $code,
                'name' => $name,
                'credits' => $credits,
                'type' => $area,
                'area' => $area,
                'prerequisites' => $idx > 3 ? [$pool[max(0, $idx - 3)][0]] : [],
                'outcomes' => [$this->courseOutcome($name, $area)],
            ];
            $creditTotal += $credits;
            $idx++;
        }
        $cyclesOut = [];
        for ($i = 1; $i <= $cycles; $i++) {
            $cyclesOut[] = ['cycle' => $i, 'courses' => $perCycle[$i]];
        }
        return [
            'faculty' => $faculty,
            'program' => $program,
            'duration_cycles' => $cycles,
            'target_credits' => $targetCredits,
            'estimated_credits' => $creditTotal,
            'profile_text' => $profile,
            'emphasis' => $emphasis,
            'version_note' => 'Propuesta preliminar generada para revisión curricular. Requiere validación por comité académico.',
            'cycles' => $cyclesOut,
            'competency_map' => [
                ['competency' => 'Resuelve problemas de la profesión con fundamentos científicos, pensamiento crítico y responsabilidad ética.', 'evidence' => 'Proyectos, estudios de caso, prácticas y evaluaciones integradoras.'],
                ['competency' => 'Integra servicio, ética, dignidad humana y cosmovisión bíblico-cristiana en decisiones profesionales pertinentes.', 'evidence' => 'Reflexiones académicas, proyectos de servicio, análisis de casos y desempeño profesional supervisado.'],
                ['competency' => 'Comunica resultados técnicos o profesionales de manera clara, rigurosa y colaborativa.', 'evidence' => 'Informes, exposiciones, sustentaciones y productos académicos.'],
                ['competency' => 'Desarrolla investigación formativa aplicada a necesidades reales del entorno.', 'evidence' => 'Protocolos, reportes, productos de investigación y trabajo final.'],
            ],
            'alerts' => [
                'Verificar que los créditos totales coincidan con la normativa académica vigente.',
                'Revisar prerrequisitos con dirección de escuela y comité curricular.',
                'Validar denominación oficial de cursos, códigos, horas teóricas/prácticas y sumillas.',
                'Ajustar integración fe-aprendizaje a cada curso sin forzar contenidos doctrinales ajenos a la naturaleza de la asignatura.',
            ],
        ];
    }

    private function courseOutcome(string $course, string $area): string
    {
        $norm = Support::normalize($course);
        if (str_contains($norm, 'program')) return 'Implementa soluciones básicas mediante algoritmos, estructuras de control y buenas prácticas de programación.';
        if (str_contains($norm, 'base_de_datos')) return 'Diseña estructuras de datos persistentes aplicando modelamiento, consultas y criterios de integridad.';
        if (str_contains($norm, 'investig')) return 'Formula y desarrolla productos de investigación formativa con rigurosidad metodológica y ética.';
        if (str_contains($norm, 'etica') || str_contains($norm, 'servicio')) return 'Analiza decisiones profesionales desde responsabilidad ética, servicio y respeto por la dignidad humana.';
        if (str_contains($norm, 'cosmovision')) return 'Relaciona principios de cosmovisión bíblico-cristiana con la formación integral y el servicio profesional.';
        return 'Aplica fundamentos de ' . mb_strtolower($course, 'UTF-8') . ' para resolver situaciones académicas y profesionales pertinentes.';
    }

    private function buildPlanPrompt(string $faculty, string $program, int $cycles, int $credits, string $profile, string $emphasis, array $plan): string
    {
        $json = json_encode($plan, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        return CurriculumGuidelines::systemPrompt() . "\n\n" . <<<PROMPT
Actúa como asesor curricular universitario. Revisa la siguiente propuesta preliminar de plan de estudios y entrega recomendaciones puntuales.

Datos:
- Facultad: {$faculty}
- Programa: {$program}
- Duración: {$cycles} ciclos
- Créditos meta: {$credits}
- Perfil de egreso: {$profile}
- Énfasis: {$emphasis}

Propuesta JSON:
{$json}

Devuelve solo una revisión en Markdown con estas secciones:
1. Diagnóstico de coherencia curricular
2. Recomendaciones para malla curricular
3. Recomendaciones para mapa de competencias
4. Alertas de versión antes de aprobación
5. Observación sobre integración fe-aprendizaje sobria y pertinente
PROMPT;
    }

    private function planMarkdown(array $plan): string
    {
        $md = '# Plan de estudios preliminar: ' . ($plan['program'] ?? '') . "\n\n";
        $md .= '- Facultad: ' . ($plan['faculty'] ?? '') . "\n";
        $md .= '- Duración: ' . ($plan['duration_cycles'] ?? '') . " ciclos\n";
        $md .= '- Créditos estimados: ' . ($plan['estimated_credits'] ?? '') . ' / meta ' . ($plan['target_credits'] ?? '') . "\n";
        $md .= '- Énfasis: ' . ($plan['emphasis'] ?? '') . "\n\n";
        $md .= "## Malla curricular por ciclo\n\n";
        foreach (($plan['cycles'] ?? []) as $cycle) {
            $md .= '### Ciclo ' . ($cycle['cycle'] ?? '') . "\n";
            foreach (($cycle['courses'] ?? []) as $c) {
                $md .= '- **' . ($c['code'] ?? '') . ' · ' . ($c['name'] ?? '') . '** (' . ($c['credits'] ?? '') . ' cr.) — ' . ($c['area'] ?? '') . "\n";
            }
            $md .= "\n";
        }
        $md .= "## Mapa de competencias\n\n";
        foreach (($plan['competency_map'] ?? []) as $m) {
            $md .= '- **Competencia:** ' . ($m['competency'] ?? '') . "\n  - Evidencia: " . ($m['evidence'] ?? '') . "\n";
        }
        $md .= "\n## Alertas curriculares\n\n";
        foreach (($plan['alerts'] ?? []) as $a) {
            $md .= '- ' . $a . "\n";
        }
        return $md;
    }

    private function matrixFromPlan(array $plan): array
    {
        $rows = [];
        foreach (($plan['cycles'] ?? []) as $cycle) {
            foreach (($cycle['courses'] ?? []) as $c) {
                $rows[] = [
                    'cycle' => $cycle['cycle'] ?? '',
                    'code' => $c['code'] ?? '',
                    'name' => $c['name'] ?? '',
                    'credits' => $c['credits'] ?? '',
                    'area' => $c['area'] ?? '',
                    'prerequisites' => implode(', ', $c['prerequisites'] ?? []),
                ];
            }
        }
        return $rows;
    }

    private function courseKey(array $course): string
    {
        $code = Support::normalize((string)($course['code'] ?? ''));
        $name = Support::normalize((string)($course['name'] ?? ''));
        return $code !== '' ? $code : $name;
    }

    private function flatCourses(array $plan): array
    {
        $out = [];
        foreach (($plan['cycles'] ?? []) as $cycle) {
            foreach (($cycle['courses'] ?? []) as $course) {
                $course['cycle'] = $cycle['cycle'] ?? null;
                $out[$this->courseKey($course)] = $course;
            }
        }
        return $out;
    }

    private function comparePlans(array $a, array $b): array
    {
        $ca = $this->flatCourses($a['plan_json'] ?? []);
        $cb = $this->flatCourses($b['plan_json'] ?? []);
        $added = array_values(array_diff_key($cb, $ca));
        $removed = array_values(array_diff_key($ca, $cb));
        $changed = [];
        foreach ($ca as $key => $old) {
            if (!isset($cb[$key])) continue;
            $new = $cb[$key];
            if ((string)($old['credits'] ?? '') !== (string)($new['credits'] ?? '') || (string)($old['cycle'] ?? '') !== (string)($new['cycle'] ?? '') || (string)($old['area'] ?? '') !== (string)($new['area'] ?? '')) {
                $changed[] = ['before' => $old, 'after' => $new];
            }
        }
        return [
            'from' => ['id' => $a['id'], 'version_no' => $a['version_no'], 'title' => $a['title']],
            'to' => ['id' => $b['id'], 'version_no' => $b['version_no'], 'title' => $b['title']],
            'summary' => [
                'added_courses' => count($added),
                'removed_courses' => count($removed),
                'changed_courses' => count($changed),
            ],
            'added' => $added,
            'removed' => $removed,
            'changed' => $changed,
        ];
    }

    private function audit(int $userId, string $action, array $payload): void
    {
        try {
            $stmt = $this->pdo->prepare('INSERT INTO curriculum_audit (user_id, action, payload_json, created_at) VALUES (?, ?, ?, ?)');
            $stmt->execute([$userId, $action, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), Support::now()]);
        } catch (Throwable $e) {
            // Audit must not block the wizard.
        }
    }

    /**
     * Prompt rápido para revisión generativa de planes curriculares.
     *
     * Este método existe como versión compacta para evitar timeouts largos
     * en Ollama y para no bloquear la API. Acepta argumentos variables porque
     * distintas versiones del controlador pueden llamarlo con firmas diferentes.
     */
    private function buildPlanReviewPromptFast(...$args): string
    {
        $payload = [];

        foreach ($args as $index => $arg) {
            if (is_array($arg) || is_object($arg)) {
                $payload['arg_' . $index] = $arg;
            } else {
                $payload['arg_' . $index] = (string)$arg;
            }
        }

        $json = json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT
        );

        if ($json === false || trim((string)$json) === '') {
            $json = '{}';
        }

        return
            "Eres JoMelAI Curriculista UPeU. Revisa el siguiente plan curricular de forma breve, técnica y accionable.\n\n" .
            "Criterios obligatorios:\n" .
            "1. No inventes datos que no estén en el payload.\n" .
            "2. Identifica fortalezas curriculares.\n" .
            "3. Identifica riesgos o vacíos: créditos, horas, ciclos, prerrequisitos, progresión, perfil de egreso, competencias y evidencias.\n" .
            "4. Sugiere mejoras concretas y priorizadas.\n" .
            "5. Usa lenguaje académico sobrio, compatible con una institución adventista.\n" .
            "6. Responde máximo en 900 palabras.\n\n" .
            "Formato de respuesta:\n" .
            "## Revisión rápida del plan\n" .
            "### Fortalezas\n" .
            "### Alertas curriculares\n" .
            "### Recomendaciones priorizadas\n" .
            "### Siguiente acción sugerida\n\n" .
            "Payload del plan:\n" .
            $json;
    }


}
