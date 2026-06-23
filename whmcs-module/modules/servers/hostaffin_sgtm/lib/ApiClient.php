<?php
/**
 * Tiny HTTP client for talking to the Hostaffin Control Plane.
 */

class Hostaffin_ApiClient
{
    private string $baseUrl;
    private string $apiKey;
    private int $timeout = 30;

    public function __construct(string $baseUrl, string $apiKey, int $timeout = 30)
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->apiKey  = $apiKey;
        $this->timeout = $timeout;
    }

    /**
     * Build a client from WHMCS $params['server'] / module options.
     *
     * @param array $params
     * @return self
     */
    public static function fromModuleParams(array $params): self
    {
        $base = $params['serverhttpprefix'] . $params['serverhostname']
              . ($params['serverport'] ? ':' . $params['serverport'] : '');
        if (empty($base) || $base === ':') {
            $base = getenv('HOSTAFFIN_API_URL') ?: 'http://localhost:8080';
        }
        $key = $params['serverpassword'] ?? (getenv('HOSTAFFIN_API_KEY') ?: '');
        return new self($base, $key);
    }

    public function get(string $path): array
    {
        return $this->request('GET', $path);
    }

    public function post(string $path, array $body = []): array
    {
        return $this->request('POST', $path, $body);
    }

    public function put(string $path, array $body = []): array
    {
        return $this->request('PUT', $path, $body);
    }

    public function delete(string $path): array
    {
        return $this->request('DELETE', $path);
    }

    private function request(string $method, string $path, array $body = null): array
    {
        $url = $this->baseUrl . $path;
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $this->timeout,
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Accept: application/json',
                'X-Api-Key: ' . $this->apiKey,
            ],
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        }
        $raw = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);
        if ($raw === false) {
            throw new RuntimeException("Hostaffin API unreachable: $err");
        }
        $decoded = json_decode((string) $raw, true) ?? [];
        if ($code >= 400) {
            $msg = $decoded['error']['message'] ?? "HTTP $code";
            throw new RuntimeException("Hostaffin API error ($code): $msg");
        }
        return is_array($decoded) ? $decoded : [];
    }
}