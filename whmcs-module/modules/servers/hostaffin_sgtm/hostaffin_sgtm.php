<?php
/**
 * Hostaffin sGTM Hosting Platform — WHMCS Server Module
 *
 * @package    Hostaffin_sGTM
 * @author     Hostaffin Ltd.
 * @copyright  Copyright (c) 2026 Hostaffin Ltd.
 * @license    Proprietary
 * @link       https://hostaffin.com
 */

if (!defined('WHMCS')) {
    die('Access Denied');
}

require_once __DIR__ . '/lib/ApiClient.php';
require_once __DIR__ . '/lib/Hooks.php';

/* ─────────────────────────── Module metadata ─────────────────────────── */

function hostaffin_sgtm_MetaData()
{
    return [
        'DisplayName'        => 'Hostaffin sGTM Hosting',
        'APIVersion'         => '1.2',
        'RequiresServer'     => false,
        'DefaultNonSSLPort'  => 80,
        'DefaultSSLPort'     => 443,
    ];
}

/* ───────────────────────── Configurable options ───────────────────────── */

function hostaffin_sgtm_ConfigOptions()
{
    return [
        'plan_slug' => [
            'FriendlyName' => 'Plan',
            'Type'         => 'dropdown',
            'Options'      => 'starter,Starter;growth,Growth;agency,Agency',
            'Description'  => 'Internal plan slug',
            'Default'      => 'starter',
        ],
        'edge_hostname' => [
            'FriendlyName' => 'Edge Hostname (read-only)',
            'Type'         => 'text',
            'Description'  => 'Auto-assigned after provisioning',
            'Size'         => 40,
            'ReadOnly'     => true,
        ],
    ];
}

/* ─────────────────────────── Lifecycle hooks ─────────────────────────── */

function hostaffin_sgtm_CreateAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $planSlug = $params['configoption1'] ?? 'starter';

        $resp = $client->post('/api/services', [
            'whmcs_service_id' => (int) $params['serviceid'],
            'whmcs_client_id'  => (int) $params['userid'],
            'plan_slug'        => $planSlug,
            'domain'           => $params['domain'] ?? '',
        ]);
        if (!in_array($resp['status'] ?? '', ['pending', 'active'], true)) {
            return "Provisioning failed: " . ($resp['error']['message'] ?? 'unknown');
        }
        if (!empty($resp['edge_hostname'])) {
            Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'edge_hostname', $resp['edge_hostname']);
        }
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'service_id', $resp['id'] ?? '');
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'plan_slug', $planSlug);
        Hostaffin_Hooks::logActivity($params['pid'], "Service #{$params['serviceid']} created via Hostaffin sGTM");
        return 'success';
    } catch (Throwable $e) {
        Hostaffin_Hooks::logActivity(0, "Hostaffin CreateAccount error: " . $e->getMessage());
        return $e->getMessage();
    }
}

function hostaffin_sgtm_SuspendAccount($params)
{
    return _hostaffin_sgtm_simplePost($params, 'suspend');
}

function hostaffin_sgtm_UnsuspendAccount($params)
{
    return _hostaffin_sgtm_simplePost($params, 'unsuspend');
}

function hostaffin_sgtm_TerminateAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        if ($sid) $client->delete("/api/services/{$sid}");
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

function hostaffin_sgtm_ChangePackage($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        $planSlug = $params['configoption1'] ?? 'starter';
        if ($sid) {
            $client->post("/api/services/{$sid}/upgrade", ['plan_slug' => $planSlug]);
        }
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'plan_slug', $planSlug);
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

function _hostaffin_sgtm_simplePost($params, string $action)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        if ($sid) $client->post("/api/services/{$sid}/{$action}");
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

/* ───────────────────────── Client-area buttons ───────────────────────── */

function hostaffin_sgtm_ClientAreaCustomButtonArray()
{
    return [
        'Restart Container'        => 'restart',
        'Manage Custom Domain'     => 'addDomain',
        'Verify DNS'               => 'verifyDomain',
        'Upgrade Plan'             => 'upgrade',
        'Manage Custom Loader'     => 'viewLoader',
        'Manage Cookie Extensions' => 'viewCookies',
    ];
}

/* ───────────────────────── Client-area actions ───────────────────────── */

/**
 * Render the main client-area panel.
 */
function hostaffin_sgtm_ClientAreaOutput($params)
{
    $serviceId = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
    if (!$serviceId) {
        return '<div class="alert alert-warning">Service is not yet provisioned.</div>';
    }

    // Handle state-changing actions BEFORE rendering so we can show success
    $flash = _hostaffin_sgtm_dispatchAction($params, $serviceId);
    if ($flash && ($flash['redirect'] ?? false)) {
        header('Location: ' . $flash['redirect']);
        exit;
    }

    $vars = _hostaffin_sgtm_fetchAll($params, $serviceId);
    if ($vars['__error'] ?? null) {
        return '<div class="alert alert-danger">' . htmlspecialchars($vars['__error']) . '</div>';
    }
    $vars['__flash'] = $flash;
    $vars['__action_url'] = $params['serverhttpprefix'] . $params['serverhostname']
                          . ($params['serverport'] ? ':' . $params['serverport'] : '')
                          . '/clientarea.php?action=productdetails&id=' . $params['serviceid']
                          . '&modop=custom&a=ClientArea';
    // Build the WHMCS-issued CSRF token for form actions
    $vars['__csrf'] = $_SESSION['token'] ?? '';
    // WHMCS submits custom-button actions via these GET params
    $vars['__action_path'] = '/modules/servers/hostaffin_sgtm/hostaffin_sgtm.php';

    $tpl = __DIR__ . '/templates/clientarea.tpl';
    return Hostaffin_Hooks::render($tpl, $vars);
}

/* Dispatch table — called before template renders.
 * Each action reads $_POST, calls the API, and returns a flash message. */
function _hostaffin_sgtm_dispatchAction(array $params, string $serviceId): array
{
    // WHMCS passes "a" param for ClientAreaOutput actions
    $a = $_GET['a'] ?? ($_POST['a'] ?? '');
    $do = $_POST['do'] ?? '';
    if (!$do) return [];

    // CSRF guard for everything except read-only 'show' actions
    Hostaffin_Hooks::checkCsrf();

    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);

        switch ($do) {

            /* ── Domain ── */
            case 'addDomain':
                $domain = trim($_POST['domain'] ?? '');
                if (!$domain) return ['type' => 'error', 'msg' => 'Domain is required.'];
                $resp = $client->post("/api/services/{$serviceId}/domains", [
                    'domain'     => $domain,
                    'is_primary' => !empty($_POST['is_primary']),
                ]);
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Unknown error'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Custom domain added: $domain");
                return ['type' => 'success', 'msg' => "Domain $domain added. Follow the DNS instructions shown below to verify it."];

            case 'verifyDomain':
                $domainId = $_POST['domain_id'] ?? '';
                if (!$domainId) return ['type' => 'error', 'msg' => 'Missing domain id.'];
                $resp = $client->post("/api/domains/{$domainId}/verify");
                if (!empty($resp['verified'])) {
                    Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Domain verified (id={$domainId})");
                    return ['type' => 'success', 'msg' => 'DNS verified! SSL certificate will be issued shortly.'];
                }
                return ['type' => 'error', 'msg' => 'Verification failed: ' . ($resp['reason'] ?? 'unknown')];

            case 'deleteDomain':
                $domainId = $_POST['domain_id'] ?? '';
                if (!$domainId) return ['type' => 'error', 'msg' => 'Missing domain id.'];
                $client->delete("/api/domains/{$domainId}");
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Custom domain removed (id={$domainId})");
                return ['type' => 'success', 'msg' => 'Domain removed.'];

            /* ── Loaders ── */
            case 'createLoader':
                $resp = $client->post("/api/services/{$serviceId}/loaders", _hostaffin_sgtm_loaderPayloadFromPost());
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Failed'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Custom loader created: " . ($resp['loader']['loader_id'] ?? ''));
                return ['type' => 'success', 'msg' => 'Loader created. Use the snippet below in your site.'];

            case 'updateLoader':
                $lid = $_POST['loader_id'] ?? '';
                if (!$lid) return ['type' => 'error', 'msg' => 'Missing loader id.'];
                $resp = $client->put("/api/loaders/{$lid}/config", _hostaffin_sgtm_loaderPayloadFromPost());
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Failed'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Loader updated: {$lid}");
                return ['type' => 'success', 'msg' => 'Loader updated.'];

            case 'regenerateLoader':
                $lid = $_POST['loader_id'] ?? '';
                if (!$lid) return ['type' => 'error', 'msg' => 'Missing loader id.'];
                $resp = $client->post("/api/loaders/{$lid}/regenerate");
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Failed'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Loader rotated: {$lid} → {$resp['new_id']}");
                return ['type' => 'success', 'msg' => "Loader rotated. Old id: {$resp['old_id']}, new id: {$resp['new_id']}. Update your site."];

            case 'toggleLoader':
                $lid = $_POST['loader_id'] ?? '';
                $op  = $_POST['op'] ?? '';
                if (!$lid || !in_array($op, ['enable', 'disable'], true)) {
                    return ['type' => 'error', 'msg' => 'Bad toggle request.'];
                }
                $client->post("/api/loaders/{$lid}/{$op}");
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Loader {$op}d: {$lid}");
                return ['type' => 'success', 'msg' => "Loader {$op}d."];

            /* ── Cookie Extensions ── */
            case 'createCookie':
                $payload = [
                    'cookie_name'    => trim($_POST['cookie_name'] ?? ''),
                    'vendor_url'     => trim($_POST['vendor_url'] ?? ''),
                    'new_lifetime_s' => (int) ($_POST['new_lifetime_s'] ?? 0),
                    'path'           => trim($_POST['path'] ?? '/'),
                    'secure'         => !empty($_POST['secure']),
                    'http_only'      => !empty($_POST['http_only']),
                    'same_site'      => $_POST['same_site'] ?? 'Lax',
                ];
                if ($_POST['cookie_domain'] ?? '') {
                    $payload['cookie_domain'] = trim($_POST['cookie_domain']);
                }
                $resp = $client->post("/api/services/{$serviceId}/cookie-extensions", $payload);
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Failed'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Cookie extension added: " . $payload['cookie_name']);
                return ['type' => 'success', 'msg' => 'Cookie extension added.'];

            case 'updateCookie':
                $cid = $_POST['cookie_id'] ?? '';
                if (!$cid) return ['type' => 'error', 'msg' => 'Missing cookie id.'];
                $payload = [
                    'vendor_url'     => trim($_POST['vendor_url'] ?? ''),
                    'new_lifetime_s' => (int) ($_POST['new_lifetime_s'] ?? 0),
                    'path'           => trim($_POST['path'] ?? '/'),
                    'secure'         => !empty($_POST['secure']),
                    'http_only'      => !empty($_POST['http_only']),
                    'same_site'      => $_POST['same_site'] ?? 'Lax',
                    'is_active'      => !empty($_POST['is_active']),
                ];
                if (isset($_POST['cookie_domain'])) {
                    $payload['cookie_domain'] = trim($_POST['cookie_domain']);
                }
                $resp = $client->put("/api/cookie-extensions/{$cid}", $payload);
                if (!empty($resp['error'])) return ['type' => 'error', 'msg' => $resp['error']['message'] ?? 'Failed'];
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Cookie extension updated: {$cid}");
                return ['type' => 'success', 'msg' => 'Cookie extension updated.'];

            case 'toggleCookie':
                $cid = $_POST['cookie_id'] ?? '';
                if (!$cid) return ['type' => 'error', 'msg' => 'Missing cookie id.'];
                // Fetch, toggle is_active, PUT back
                $current = $client->get("/api/cookie-extensions/{$cid}");
                $next = empty($current['is_active']);
                $client->put("/api/cookie-extensions/{$cid}", ['is_active' => $next]);
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Cookie extension " . ($next ? 'enabled' : 'disabled') . ": {$cid}");
                return ['type' => 'success', 'msg' => 'Cookie extension ' . ($next ? 'enabled' : 'disabled') . '.'];

            case 'deleteCookie':
                $cid = $_POST['cookie_id'] ?? '';
                if (!$cid) return ['type' => 'error', 'msg' => 'Missing cookie id.'];
                $client->delete("/api/cookie-extensions/{$cid}");
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Cookie extension removed: {$cid}");
                return ['type' => 'success', 'msg' => 'Cookie extension removed.'];

            /* ── Misc ── */
            case 'restart':
                $client->post("/api/services/{$serviceId}/restart");
                Hostaffin_Hooks::logActivity((int) $params['serviceid'], "Container restarted");
                return ['type' => 'success', 'msg' => 'Container restart requested.'];

            default:
                return ['type' => 'error', 'msg' => "Unknown action: $do"];
        }
    } catch (Throwable $e) {
        return ['type' => 'error', 'msg' => $e->getMessage()];
    }
}

function _hostaffin_sgtm_loaderPayloadFromPost(): array
{
    $payload = [
        'mode'           => $_POST['mode'] ?? 'live',
        'trigger_type'   => $_POST['trigger_type'] ?? 'immediate',
        'trigger_value'  => $_POST['trigger_value'] ?? '',
        'cookie_name'    => $_POST['cookie_name'] ?? '',
        'js_file_alias'  => $_POST['js_file_alias'] ?? 'gtm.js',
        'fbp_cookie_name'=> $_POST['fbp_cookie_name'] ?? '_fbp',
        'fbc_cookie_name'=> $_POST['fbc_cookie_name'] ?? '_fbc',
        'respect_dnt'    => !empty($_POST['respect_dnt']),
        'allow_bots'     => !empty($_POST['allow_bots']),
        'honor_consent'  => !empty($_POST['honor_consent']),
    ];
    // Optional vendor-mapping JSON
    $vm = trim($_POST['vendor_mapping'] ?? '');
    if ($vm) {
        $decoded = json_decode($vm, true);
        if (is_array($decoded)) $payload['vendor_mapping'] = $decoded;
    }
    return $payload;
}

function _hostaffin_sgtm_fetchAll($params, string $serviceId): array
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $service    = $client->get("/api/services/{$serviceId}");
        $usage      = $client->get("/api/services/{$serviceId}/usage");
        $loaders    = $client->get("/api/services/{$serviceId}/loaders");
        $cookies    = $client->get("/api/services/{$serviceId}/cookie-extensions");
        $domains    = $client->get("/api/services/{$serviceId}/domains");

        // Status → badge HTML for direct template inclusion
        $status = (string) ($service['status'] ?? '');
        $badgeClass = match ($status) {
            'active'       => 'ok',
            'provisioning' => 'warn',
            'suspended',
            'failed'       => 'err',
            default        => 'idle',
        };
        $service['status_badge'] = '<span class="badge ' . $badgeClass . '">' . htmlspecialchars($status ?: 'unknown', ENT_QUOTES) . '</span>';

        // Enrich domains with pre-rendered badge HTML so the template stays simple
        $enrichedDomains = [];
        foreach (($domains['items'] ?? []) as $d) {
            $verifiedBadge = !empty($d['verified'])
                ? '<span class="badge ok">verified</span>'
                : '<span class="badge warn">pending</span>';
            $sslBadge = match ($d['ssl_status'] ?? '') {
                'issued' => '<span class="badge ok">issued</span>',
                'failed' => '<span class="badge err">failed</span>',
                default  => '<span class="badge idle">' . htmlspecialchars((string)($d['ssl_status'] ?? 'pending'), ENT_QUOTES) . '</span>',
            };
            $d['verified_badge'] = $verifiedBadge;
            $d['ssl_badge']      = $sslBadge;
            $d['needs_verify']   = empty($d['verified']);
            $enrichedDomains[]   = $d;
        }

        // Enrich cookies with formatted lifetime
        $enrichedCookies = [];
        foreach (($cookies['items'] ?? []) as $c) {
            $c['lifetime_days'] = (int) round(($c['new_lifetime_s'] ?? 0) / 86400);
            $enrichedCookies[] = $c;
        }

        // Enrich loaders with their configs so the template can show alias/FBP
        $loaderCfgs = [];
        $enrichedLoaders = [];
        foreach (($loaders['items'] ?? []) as $l) {
            $full = $client->get("/api/loaders/" . $l['loader_id']);
            $cfg = $full['config'] ?? [];
            $loaderCfgs[$l['loader_id']] = $cfg;
            $loaderCfgs[$l['loader_id']]['snippet'] = $full['snippet'] ?? '';
            $loaderCfgs[$l['loader_id']]['sri_hash'] = $full['sri_hash'] ?? '';
            // Flatten config fields onto the loader so the template can use {{.js_file_alias}} etc.
            $enrichedLoaders[] = array_merge($l, [
                'js_file_alias'   => $cfg['js_file_alias']   ?? 'gtm.js',
                'fbp_cookie_name' => $cfg['fbp_cookie_name'] ?? '_fbp',
                'fbc_cookie_name' => $cfg['fbc_cookie_name'] ?? '_fbc',
                'trigger_type'    => $cfg['trigger_type']    ?? 'immediate',
                'trigger_value'   => $cfg['trigger_value']   ?? '',
                'snippet'         => $full['snippet']        ?? '',
                'sri_hash'        => $full['sri_hash']       ?? '',
            ]);
        }

        // Build the JS-alias dropdown options
        $aliasOpts = Hostaffin_Hooks::jsAliasOptions();
        $aliasOptList = [];
        foreach ($aliasOpts as $k => $v) {
            $aliasOptList[] = ['key' => $k, 'value' => $v];
        }

        return [
            'service'    => $service,
            'usage'      => $usage,
            'loaders'    => $enrichedLoaders,
            'loader_cfgs'=> $loaderCfgs,
            'cookies'    => $enrichedCookies,
            'domains'    => $enrichedDomains,
            'service_id' => $serviceId,
            'js_alias_options'    => $aliasOptList,
            'cookie_alias_presets'=> Hostaffin_Hooks::cookieAliasPresets(),
        ];
    } catch (Throwable $e) {
        return ['__error' => 'Could not load service data: ' . $e->getMessage()];
    }
}

/* ───────────────────────── Admin-only buttons ────────────────────────── */

function hostaffin_sgtm_AdminCustomButtonArray()
{
    return [
        'Force Restart'  => 'forceRestart',
        'Re-verify'      => 'reverify',
        'View Raw JSON'  => 'viewJson',
    ];
}
