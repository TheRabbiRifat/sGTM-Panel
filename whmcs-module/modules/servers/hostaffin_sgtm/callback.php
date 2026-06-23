<?php
/**
 * WHMCS webhook callback receiver.
 *
 * Configure WHMCS to POST to /modules/servers/hostaffin_sgtm/callback.php
 * with the X-Hostaffin-Signature header (HMAC-SHA256 of the raw body using
 * the shared secret).
 */

require_once __DIR__ . '/../../../init.php';
require_once __DIR__ . '/lib/Hooks.php';

header('Content-Type: application/json');

$raw = file_get_contents('php://input') ?: '';
$secret = getenv('HOSTAFFIN_WEBHOOK_SECRET') ?: '';
$signature = $_SERVER['HTTP_X_HOSTAFFIN_SIGNATURE'] ?? '';

if ($secret && !hash_equals(hash_hmac('sha256', $raw, $secret), $signature)) {
    http_response_code(401);
    echo json_encode(['error' => 'invalid signature']);
    exit;
}

$event = json_decode($raw, true);
if (!is_array($event)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid body']);
    exit;
}

$type = $event['event'] ?? 'unknown';
$payload = $event['payload'] ?? [];
$serviceId = $payload['whmcs_service_id'] ?? null;
$message = match ($type) {
    'service.provisioned' => "Your sGTM service is ready: {$payload['edge_hostname']}",
    'service.failed'      => "Provisioning failed: {$payload['reason']}",
    'service.suspended'   => "Your sGTM service has been suspended.",
    'service.unsuspended' => "Your sGTM service has been reactivated.",
    'domain.verified'     => "Domain verified: {$payload['domain']}",
    'ssl.issued'          => "SSL certificate issued for {$payload['domain']}",
    'ssl.failed'          => "SSL issuance failed for {$payload['domain']}",
    'quota.exceeded'      => "Your plan's request quota has been exceeded.",
    default               => "Update: $type",
};

if ($serviceId) {
    Hostaffin_Hooks::logActivity((int) $serviceId, "[Hostaffin] $message");
}

echo json_encode(['ok' => true, 'event' => $type]);