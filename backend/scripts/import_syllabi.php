<?php
require __DIR__ . '/../src/Support.php';
Support::bootstrap();
spl_autoload_register(function ($class) {
    $file = __DIR__ . '/../src/' . $class . '.php';
    if (is_file($file)) require $file;
});

$options = getopt('', ['file:', 'delimiter::', 'chunk::', 'replace::']);
$file = $options['file'] ?? Support::config('default_csv_path');
$delimiter = $options['delimiter'] ?? Support::config('default_csv_delimiter');
$chunk = (int)($options['chunk'] ?? Support::config('default_csv_chunk'));
$replace = isset($options['replace']) && in_array((string)$options['replace'], ['1','true','yes'], true);

$result = (new CsvImporter())->import($file, $delimiter, $chunk, $replace);
echo json_encode(['ok' => true, 'result' => $result], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL;
