#!/usr/bin/env php
<?php

$api_base      = getenv('LITELLM_API_BASE') ?: '';
$api_key       = getenv('LITELLM_API_KEY') ?: '';
$model         = getenv('LITELLM_MODEL') ?: ''; 
$system        = getenv('LITELLM_SYSTEM') ?: '';
$content       = getenv('LITELLM_DATA_CONTENT') ?: '';
$user          = getenv('LITELLM_USER_PROMPT') ?: '';

if($content != "" &&  $user != "" ) {  
   $user_prompt = $content.$user;

} elseif ($argc < 2) {
   echo "Usage: ./<script_name>.sh \"Your question here\"\n";
   exit(1);

} else {
  unset($argv[0]);
  $user_prompt = implode(' ', $argv);

}

$payload = [
    'model' => $model,
    'messages' => [
        ['role' => 'system', 'content' => $system],
        ['role' => 'user', 'content' => $user_prompt]
    ],
    'stream' => true
];

$ch = curl_init("$api_base/chat/completions");

curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => json_encode($payload),
    CURLOPT_HTTPHEADER     => [
        "Content-Type: application/json",
        "Authorization: Bearer $api_key"
    ],
    CURLOPT_WRITEFUNCTION  => function($ch, $data) {
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        if ($httpCode >= 400) {
            echo "\n[API ERROR $httpCode]: " . trim($data) . "\n";
            return strlen($data);
        }

        $lines = explode("\n", $data);
        foreach ($lines as $line) {
            $line = trim($line);
            if (empty($line) || $line === 'data: [DONE]') {
                continue;
            }
            if (strpos($line, 'data: ') === 0) {
                $json_str = substr($line, 6);
                $json = json_decode($json_str, true);
                if (isset($json['choices'][0]['delta']['content'])) {
                    echo $json['choices'][0]['delta']['content'];
                    flush();
                }
            }
        }
        return strlen($data);
    }
]);

curl_exec($ch);
if (curl_errno($ch)) {
    echo "\n[cURL ERROR]: " . curl_error($ch) . "\n";
}
curl_close($ch);
echo "\n";
